// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/@openzeppelin/contracts/math/SafeMath.sol";
import "./FlightSuretyData.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner; // Account used to deploy contract

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }
    mapping(bytes32 => Flight) private flights;

    // Airline satus codes
    uint8 private constant UNREGISTERED = 0; // this must be 0
    uint8 private constant IN_REGISTRATION = 10;
    uint8 private constant REGISTERED = 20;
    uint8 private constant FUNDED = 30;

    struct Airline {
        uint8 status;
        uint256 votes;
    }
    mapping(address => Airline) private mapAirlines;
    address[] private airlines = new address[](0);
    uint8 private constant M_CONSENSUS = 4;
    uint256 private numAirlinesConsensus;
    mapping(address => address[]) private mapQueueAirlines;

    /* ******************************* Management of contract ***********************************/
    bool private operational = true;
    FlightSuretyData private flightSuretyData;
    bool private firstTime = true; // used to check that registerFirstAirline is only called once

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(
            operational,
            "FlightSuretyApp contract is currently not operational"
        );
        _;
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires the caller to be a registered airline
     */
    modifier requireRegisteredAirline() {
        require(
            mapAirlines[msg.sender].status == REGISTERED,
            "Caller must be a registered airline"
        );
        _;
    }

    /**
     * @dev Modifier that requires airline to be funded
     */
    modifier requireFundedAirline() {
        require(
            mapAirlines[msg.sender].status == FUNDED,
            "Airline must be funded"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
     * @dev Contract constructor
     *
     */
    constructor(address dataContractAddress, address firstAirline) public {
        require(dataContractAddress != address(0));
        contractOwner = msg.sender;
        flightSuretyData = FlightSuretyData(dataContractAddress);
        _registerAirline(firstAirline);
        airlines.push(firstAirline);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns (bool) {
        return operational;
    }

    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                 FUNCTIONS FOR TESTING ONLY                               */
    /********************************************************************************************/

    /**
     * @dev For testing, always returns true
     *
     */
    function testIsOperational()
        public
        view
        requireIsOperational
        returns (bool)
    {
        return true;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *
     */
    function registerAirline(address airline)
        external
        requireIsOperational
        requireFundedAirline
        returns (bool success, uint256 votes)
    {
        if (mapAirlines[airline].status == UNREGISTERED) {
            mapAirlines[airline] = Airline({status: UNREGISTERED, votes: 0});
            airlines.push(airline);
        }

        // check consensus
        if (numAirlinesConsensus < M_CONSENSUS) {
            success = _registerAirline(airline);
            mapAirlines[airline].status = REGISTERED;
        } else {
            uint256 currentVotes = mapQueueAirlines[airline].length;
            if (currentVotes == 0) {
                mapQueueAirlines[airline] = new address[](0);
                mapQueueAirlines[airline].push(msg.sender);
                success = false;
                votes = 1;
                mapAirlines[airline].status = IN_REGISTRATION;
                mapAirlines[airline].votes = votes;
            } else {
                // prevent double voting
                uint256 counter = 0;
                for (; counter < currentVotes; counter++) {
                    if (mapQueueAirlines[airline][counter] == msg.sender)
                        // double vote by msg.sender
                        break;
                }
                if (counter == currentVotes)
                    // no double vote by msg.sender, add vote
                    mapQueueAirlines[airline].push(msg.sender);
                // update votes
                votes = mapQueueAirlines[airline].length;
                if (votes.mul(2) >= numAirlinesConsensus) {
                    success = _registerAirline(airline);
                    mapAirlines[airline].status = REGISTERED;
                    mapAirlines[airline].votes = votes;
                } else {
                    success = false;
                    mapAirlines[airline].votes = votes;
                }
            }
        }
        return (success, votes);
    }

    /**
     * @dev Register a future flight for insuring.
     *
     */
    function _registerAirline(address airline)
        private
        requireIsOperational
        returns (bool success)
    {
        require(
            mapAirlines[airline].status == UNREGISTERED ||
                mapAirlines[airline].status == IN_REGISTRATION
        );
        mapAirlines[airline].status = REGISTERED;
        numAirlinesConsensus++;
        if (mapQueueAirlines[airline].length != 0)
            delete mapQueueAirlines[airline];
        return true;
    }

    /**
     * @dev Check if an airline is in the registration process
     *
     */
    function isInRegistrationAirline(address airline)
        external
        view
        returns (bool)
    {
        return mapAirlines[airline].status == IN_REGISTRATION;
    }

    /**
     * @dev Check if an airline is registered
     *
     */
    function isRegisteredAirline(address airline) external view returns (bool) {
        return mapAirlines[airline].status == REGISTERED;
    }

    /**
     * @dev Allow airline to fund itself if registered
     *
     */
    function fund()
        external
        payable
        requireIsOperational
        requireRegisteredAirline
    {
        require(msg.value == 10 ether);
        mapAirlines[msg.sender].status = FUNDED;
        flightSuretyData.fund{value: msg.value}(msg.sender);
    }

    /**
     * @dev Check funding of airline
     *
     */
    function isFundedAirline(address airline) external view returns (bool) {
        return mapAirlines[airline].status == FUNDED;
    }

    /**
     * @dev Return airlines that are registered
     *
     */
    function getAirlines() external view returns (address[] memory) {
        return airlines;
    }

    /**
     * @dev Return airline status
     *
     */
    function getAirlineStatus(address airline) external view returns (uint8) {
        return mapAirlines[airline].status;
    }

    /**
     * @dev Register a flight
     *
     */
    function registerFlight() external pure {}

    /**
     * @dev Called after oracle has updated flight status
     *
     */
    function processFlightStatus(
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) private {
        if (statusCode == STATUS_CODE_UNKNOWN) return;
        else if (statusCode == STATUS_CODE_LATE_AIRLINE)
            flightSuretyData.creditInsurees(airline, flight, timestamp, 3, 2);
        else flightSuretyData.terminateInsurance(airline, flight, timestamp);
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(
        address airline,
        string memory flight,
        uint256 timestamp
    ) external {
        uint8 index = getRandomIndex(msg.sender);
        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        ResponseInfo storage newResponseInfo = oracleResponses[key];
        newResponseInfo.requester = msg.sender;
        newResponseInfo.isOpen = true;
        delete newResponseInfo.responses[STATUS_CODE_UNKNOWN];
        delete newResponseInfo.responses[STATUS_CODE_ON_TIME];
        delete newResponseInfo.responses[STATUS_CODE_LATE_AIRLINE];
        delete newResponseInfo.responses[STATUS_CODE_LATE_WEATHER];
        delete newResponseInfo.responses[STATUS_CODE_LATE_TECHNICAL];
        delete newResponseInfo.responses[STATUS_CODE_LATE_OTHER];

        emit OracleRequest(index, airline, flight, timestamp);
    }

    // region PASSENGER MANAGAMENT
    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy(
        address airline,
        string memory flight,
        uint256 timestamp
    ) external payable {
        // check that inurance premium is max 1 ether
        require(msg.value <= 1 ether);
        // check that the insurance is funded
        require(mapAirlines[airline].status == FUNDED);
        // forward funds to data contract
        flightSuretyData.buy{value: msg.value}(
            airline,
            flight,
            timestamp,
            msg.sender
        );
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay() external {
        flightSuretyData.pay(msg.sender);
    }

    /**
     *  @dev Return available credit
     *
     */
    function getCredit() external view returns (uint256) {
        return flightSuretyData.getCredit(msg.sender);
    }

    /**
     *  @dev Return amount insured
     *
     */
    function getInsurance(
        address airline,
        string memory flight,
        uint256 timestamp
    ) external view returns (uint256) {
        return
            flightSuretyData.getInsurance(
                msg.sender,
                airline,
                flight,
                timestamp
            );
    }

    /**
     *  @dev Get insurance keys
     *
     */
    function getActiveInsuranceKeys()
        external
        view
        returns (
            bytes32[] memory activeInsuranceKeys,
            uint256 nActiveInsurances
        )
    {
        return flightSuretyData.getActiveInsuranceKeys(msg.sender);
    }

    /**
     *  @dev Get insurance data
     *
     */
    function getInsuranceData(bytes32 key)
        external
        view
        returns (
            address airline,
            string memory flight,
            uint256 timestamp
        )
    {
        return flightSuretyData.getInsuranceData(key);
    }

    // region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester; // Account that requested status
        bool isOpen; // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses; // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    );

    // Register an oracle with the contract
    function registerOracle() external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes() external view returns (uint8[3] memory) {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) external {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request"
        );

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information

        emit OracleReport(airline, flight, timestamp, statusCode);

        if (
            oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES
        ) {
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);
            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
            // mark Oracle as closed
            oracleResponses[key].isOpen = false;
        }
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account)
        internal
        returns (uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(blockhash(block.number - nonce++), account)
                )
            ) % maxValue
        );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    // endregion
}
