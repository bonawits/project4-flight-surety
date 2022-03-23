// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import "../node_modules/@openzeppelin/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false
    mapping(address => bool) private authorizedCallers; // Authorized contracts callers

    mapping(address => bool) private fundedAirlines;

    // Passenger insurance
    struct InsuranceData {
        address airline;
        string flight;
        uint256 timestamp;
    }

    mapping(bytes32 => InsuranceData) private insuranceDataPerFlightKey;

    bytes32[] private allKeys;
    address[] private allInsurees;
    mapping(bytes32 => mapping(address => uint256)) private insurancesPerKey;
    mapping(address => uint256) private credit;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor() public {
        contractOwner = msg.sender;
    }

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
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires the function caller to be authorized
     */
    modifier requireAuthorizedCaller() {
        require(
            authorizedCallers[msg.sender],
            "Caller of FlightSuretyData is not authorized"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */
    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /**
     * @dev Add an authorized address
     *
     */
    function authorizeCaller(address _address) external requireContractOwner {
        authorizedCallers[_address] = true;
    }

    /**
     * @dev Remove an authorized address
     *
     */
    function deAuthorizeCaller(address _address) private requireContractOwner {
        authorizedCallers[_address] = false;
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
     * @dev Buy insurance for a flight
     *
     */
    function buy(
        address airline,
        string memory flight,
        uint256 timestamp,
        address insuree
    ) external payable requireAuthorizedCaller {
        bytes32 buyKey = getFlightKey(airline, flight, timestamp);
        require(insurancesPerKey[buyKey][insuree] == 0); // only one insurance allowed per passenger per flight
        //require(insurancesPerInsuree[insuree][key] == 0);
        // record insurance metadata
        insuranceDataPerFlightKey[buyKey] = InsuranceData({
            airline: airline,
            flight: flight,
            timestamp: timestamp
        }); // record meta data of insurance in smart contract
        // book insurance premium
        insurancesPerKey[buyKey][insuree] = msg.value;
        //insurancesPerInsuree[key][insuree] = msg.value;
        // add key to list of keys
        uint256 i = 0;
        for (i = 0; i < allKeys.length; i++) if (allKeys[i] == buyKey) break;
        if (i == allKeys.length)
            // first time this key appears
            allKeys.push(buyKey);
        // add insuree to list of insurees
        uint256 k = 0;
        for (k = 0; k < allInsurees.length; k++)
            if (allInsurees[i] == insuree) break;
        if (k == allInsurees.length)
            // first time this key appears
            allInsurees.push(insuree);
    }

    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsurees(
        address airline,
        string memory flight,
        uint256 timestamp,
        uint256 payOffNumerator,
        uint256 payOffDenominator
    ) external requireAuthorizedCaller {
        // get flight key
        bytes32 creditKey = getFlightKey(airline, flight, timestamp);
        // loop on insurees
        for (uint256 j = 0; j < allInsurees.length; j++) {
            // address of insuree
            address insuree = allInsurees[j];
            // multiply paid premium by payOff
            uint256 payout = (insurancesPerKey[creditKey][insuree])
                .mul(payOffNumerator)
                .div(payOffDenominator);
            // set insured amount for flight to 0
            insurancesPerKey[creditKey][insuree] = 0;
            //insurancesPerInsuree[insuree][key] = 0;
            // update insuree credit
            credit[insuree] = credit[insuree].add(payout);
        }
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay(address passenger) external requireAuthorizedCaller {
        uint256 amount = credit[passenger];
        credit[passenger] = 0;
        payable(passenger).transfer(amount);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund(address airline) external payable requireAuthorizedCaller {
        // make sure an airline is only funded once
        require(fundedAirlines[airline] == false);
        // check funding amount
        require(msg.value == 10 ether);
        // flag airline as funded
        fundedAirlines[airline] = true;
    }

    /**
     *  @dev Returns credit of a passenger
     *
     */
    function getCredit(address passenger)
        external
        view
        requireAuthorizedCaller
        returns (uint256)
    {
        return credit[passenger];
    }

    /**
     *  @dev Returns amount (premium) of passenger insurance
     *
     */
    function getInsurance(
        address passenger,
        address airline,
        string memory flight,
        uint256 timestamp
    ) external view requireAuthorizedCaller returns (uint256) {
        // get flight key
        bytes32 insuranceKey = getFlightKey(airline, flight, timestamp);
        return insurancesPerKey[insuranceKey][passenger];
    }

    /**
     *  @dev Transfers passengers paid premia to insurance definitely (because flight was not delayed due to an airline fault)
     *
     */
    function terminateInsurance(
        address airline,
        string memory flight,
        uint256 timestamp
    ) external requireAuthorizedCaller {
        // get flight key
        bytes32 key = getFlightKey(airline, flight, timestamp);
        // loop on insurees
        for (uint256 i = 0; i < allInsurees.length; i++) {
            // address of insuree
            address insuree = allInsurees[i];
            // set insured amount for flight to 0
            insurancesPerKey[key][insuree] = 0;
            //insurancesPerInsuree[insuree][key] = 0;
        }
    }

    /**
     *  @dev Returns list of active insurances' keys for a given passenger
     *
     */
    function getActiveInsuranceKeys(address insuree)
        external
        view
        requireAuthorizedCaller
        returns (
            bytes32[] memory activeInsuranceKeys,
            uint256 nActiveInsurances
        )
    {
        nActiveInsurances = 0;

        // find number of active insurances of current passenger
        for (uint256 h = 0; h < allKeys.length; h++) {
            bytes32 key1 = allKeys[h];
            if (insurancesPerKey[key1][insuree] != 0) {
                // active insurance
                nActiveInsurances++;
            }
        }

        activeInsuranceKeys = new bytes32[](nActiveInsurances);
        uint256 idx = 0;
        for (uint256 i = 0; i < allKeys.length; i++) {
            bytes32 key2 = allKeys[i];
            if (insurancesPerKey[key2][insuree] != 0) {
                // active insurance
                activeInsuranceKeys[idx] = key2;
                idx++;
            }
        }
        // we need to return the num of active insurances, otherwise too much is returned
        // if an insurance is removed before another is added
        return (activeInsuranceKeys, nActiveInsurances);
    }

    /**
     *  @dev Returns insurance data for a given key
     *
     */
    function getInsuranceData(bytes32 key)
        external
        view
        requireAuthorizedCaller
        returns (
            address airline,
            string memory flight,
            uint256 timestamp
        )
    {
        InsuranceData memory data = insuranceDataPerFlightKey[key];
        return (data.airline, data.flight, data.timestamp);
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    fallback() external {}
}
