var Test = require("../config/testConfig.js");
var BigNumber = require("bignumber.js");
const assert = require("assert");
const { time } = require("console");

contract("Flight Surety Tests", async (accounts) => {
  var config;
  before("setup contract", async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeCaller(
      config.flightSuretyApp.address
    );
  });

  describe("FlightSuretyData", () => {
    it(`has correct initial isOperational() value`, async function () {
      let status = await config.flightSuretyData.isOperational.call();
      assert.equal(status, true);
    });

    it(`blocks access to setOperatingStatus() for non contract Owner account`, async function () {
      let accessDenied = false;
      try {
        await config.flightSuretyData.setOperatingStatus(false, {
          from: config.testAddresses[2],
        });
      } catch (e) {
        accessDenied = true;
      }
      assert.equal(accessDenied, true);
    });

    it(`allows access to setOperatingStatus() for Contract Owner account`, async function () {
      let accessDenied = false;
      try {
        await config.flightSuretyData.setOperatingStatus(false);
      } catch (e) {
        accessDenied = true;
      }
      assert.equal(accessDenied, false);
      await config.flightSuretyData.setOperatingStatus(true);
    });

    it(`blocks access to functions using requireIsOperational when operating status is false`, async function () {
      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try {
        await config.flightSuretyData.testIsOperational.call();
      } catch (e) {
        reverted = true;
      }
      assert.equal(reverted, true);

      await config.flightSuretyData.setOperatingStatus(true);
    });

    it(`allows access to functions using requireIsOperational when operating status is true`, async function () {
      let reverted = false;
      try {
        await config.flightSuretyData.testIsOperational.call();
      } catch (e) {
        reverted = true;
      }
      assert.equal(reverted, false);
    });
  });

  describe("FlightSuretyApp", () => {
    it(`has correct initial isOperational() value`, async function () {
      let status = await config.flightSuretyApp.isOperational.call();
      assert.equal(status, true, "Incorrect initial operating status value");
    });

    it(`blocks access to setOperatingStatus() for non-Contract Owner account`, async function () {
      let accessDenied = false;
      try {
        await config.flightSuretyApp.setOperatingStatus(false, {
          from: config.testAddresses[2],
        });
      } catch (e) {
        accessDenied = true;
      }
      assert.equal(accessDenied, true);
    });

    it(`allows access to setOperatingStatus() for Contract Owner account`, async function () {
      let accessDenied = false;
      try {
        await config.flightSuretyApp.setOperatingStatus(false);
      } catch (e) {
        accessDenied = true;
      }
      assert.equal(accessDenied, false);

      await config.flightSuretyApp.setOperatingStatus(true);
    });

    it(`blocks access to functions using requireIsOperational when operating status is false`, async function () {
      await config.flightSuretyApp.setOperatingStatus(false);

      let reverted = false;
      try {
        await config.flightSuretyApp.testIsOperational.call();
      } catch (e) {
        reverted = true;
      }
      assert.equal(reverted, true);

      await config.flightSuretyApp.setOperatingStatus(true);
    });

    it(`allows access to functions using requireIsOperational when operating status is true`, async function () {
      let reverted = false;
      try {
        await config.flightSuretyApp.testIsOperational.call();
      } catch (e) {
        reverted = true;
      }
      assert.equal(reverted, false);
    });

    it("registers the first airline when contract is deployed", async () => {
      let firstAirline = accounts[1];
      assert.equal(firstAirline === config.firstAirline, true);
      let result = false;

      result = await config.flightSuretyApp.isRegisteredAirline.call(
        firstAirline
      );

      assert.equal(result, true);
    });

    it("prevents an airline that has insufficient funds from registering", async () => {
      let firstAirline = accounts[1];
      let secondAirline = accounts[2];
      let reverted = false;

      let isFirstAirlineRegistered =
        await config.flightSuretyApp.isRegisteredAirline.call(firstAirline);
      assert.equal(isFirstAirlineRegistered, true);
      let isFirstAirlineFunded =
        await config.flightSuretyApp.isFundedAirline.call(firstAirline);
      assert.equal(isFirstAirlineFunded, false);

      try {
        await config.flightSuretyApp.registerAirline(secondAirline, {
          from: firstAirline,
        });
      } catch (e) {
        reverted = true;
      }

      assert.equal(reverted, true);
    });

    it("allows a funded airline to register another airline", async () => {
      let firstAirline = accounts[1];
      let secondAirline = accounts[2];
      let reverted = false;

      let isFirstAirlineRegistered =
        await config.flightSuretyApp.isRegisteredAirline.call(firstAirline);
      assert.equal(isFirstAirlineRegistered, true);
      let isFirstAirlineFunded =
        await config.flightSuretyApp.isFundedAirline.call(firstAirline);
      assert.equal(isFirstAirlineFunded, false);

      await config.flightSuretyApp.fund({
        from: firstAirline,
        value: 10 * config.weiMultiple,
      });
      isFirstAirlineFunded = await config.flightSuretyApp.isFundedAirline.call(
        firstAirline
      );
      assert.equal(isFirstAirlineFunded, true);

      try {
        await config.flightSuretyApp.registerAirline(secondAirline, {
          from: firstAirline,
        });
      } catch (e) {
        reverted = true;
      }

      assert.equal(reverted, false);
    });

    it("prevents funding of a non registered airline", async () => {
      let thirdAirline = accounts[3];
      let reverted = false;

      let isThirdAirlineRegistered =
        await config.flightSuretyApp.isRegisteredAirline.call(thirdAirline);
      assert.equal(isThirdAirlineRegistered, false);

      try {
        await config.flightSuretyApp.fund({
          from: thirdAirline,
          value: 10 * config.weiMultiple,
        });
      } catch (e) {
        reverted = true;
      }

      assert.equal(reverted, true);
    });

    it("allows registered and funded airlines to register other airlines up to the 4th airline (consensus)", async () => {
      let firstAirline = accounts[1];
      let secondAirline = accounts[2];
      let thirdAirline = accounts[3];
      let fourthAirline = accounts[4];

      let isFirstAirlineFunded =
        await config.flightSuretyApp.isFundedAirline.call(firstAirline);
      assert.equal(isFirstAirlineFunded, true);
      let isSecondAirlineRegistered =
        await config.flightSuretyApp.isRegisteredAirline.call(secondAirline);
      assert.equal(isSecondAirlineRegistered, true);
      let isSecondAirlineFunded =
        await config.flightSuretyApp.isFundedAirline.call(secondAirline);
      assert.equal(isSecondAirlineFunded, false);

      await config.flightSuretyApp.fund({
        from: secondAirline,
        value: 10 * config.weiMultiple,
      });
      isSecondAirlineFunded = await config.flightSuretyApp.isFundedAirline.call(
        firstAirline
      );

      await config.flightSuretyApp.registerAirline(thirdAirline, {
        from: secondAirline,
      });
      let isThirdAirlineRegistered =
        await config.flightSuretyApp.isRegisteredAirline.call(thirdAirline);
      await config.flightSuretyApp.fund({
        from: thirdAirline,
        value: 10 * config.weiMultiple,
      });
      let isThirdAirlineFunded =
        await config.flightSuretyApp.isFundedAirline.call(thirdAirline);

      await config.flightSuretyApp.registerAirline(fourthAirline, {
        from: thirdAirline,
      });
      let isFourthAirlineRegistered =
        await config.flightSuretyApp.isRegisteredAirline.call(fourthAirline);
      await config.flightSuretyApp.fund({
        from: fourthAirline,
        value: 10 * config.weiMultiple,
      });
      let isFourthAirlineFunded =
        await config.flightSuretyApp.isFundedAirline.call(fourthAirline);

      assert.equal(isSecondAirlineFunded, true);
      assert.equal(isThirdAirlineRegistered, true);
      assert.equal(isThirdAirlineFunded, true);
      assert.equal(isFourthAirlineRegistered, true);
      assert.equal(isFourthAirlineFunded, true);
    });

    it("requires 2 airlines (50% consensus) from 4 registered and funded airlines to add a new airline", async () => {
      for (i = 1; i <= 4; i++) {
        let isAirlineFunded = await config.flightSuretyApp.isFundedAirline.call(
          accounts[i]
        );
        if (isAirlineFunded === false) break;
      }
      assert.equal(i, 5, "Airline " + i + " is not funded");

      let fifthAirline = accounts[5];
      await config.flightSuretyApp.registerAirline(fifthAirline, {
        from: accounts[2],
      });
      let statusAfterFirst =
        await config.flightSuretyApp.isRegisteredAirline.call(fifthAirline);
      await config.flightSuretyApp.registerAirline(fifthAirline, {
        from: accounts[3],
      });
      let statusAfterSecond =
        await config.flightSuretyApp.isRegisteredAirline.call(fifthAirline);

      assert.equal(statusAfterFirst, false);
      assert.equal(statusAfterSecond, true);
    });

    it("requires 3 airlines (50% consensus) from 6 registered and funded airlines to add a new airline", async () => {
      for (i = 1; i <= 4; i++) {
        let isAirlineFunded = await config.flightSuretyApp.isFundedAirline.call(
          accounts[i]
        );
        if (isAirlineFunded === false) break;
      }
      assert.equal(i, 5);

      let sixthAirline = accounts[6];
      await config.flightSuretyApp.registerAirline(sixthAirline, {
        from: accounts[2],
      });
      let statusAfterFirst =
        await config.flightSuretyApp.isRegisteredAirline.call(sixthAirline);
      await config.flightSuretyApp.registerAirline(sixthAirline, {
        from: accounts[3],
      });
      let statusAfterSecond =
        await config.flightSuretyApp.isRegisteredAirline.call(sixthAirline);
      await config.flightSuretyApp.registerAirline(sixthAirline, {
        from: accounts[4],
      });
      let statusAfterThird =
        await config.flightSuretyApp.isRegisteredAirline.call(sixthAirline);

      assert.equal(statusAfterFirst, false);
      assert.equal(statusAfterSecond, false);
      assert.equal(statusAfterThird, true);
    });

    it("allows a passenger to buy insurance for up to 1 ether", async () => {
      let firstAirline = accounts[1];
      let passenger = accounts[7];
      let flight = "ZA123";
      let timestamp = Math.floor(Date.now() / 1000);
      let premium = 1;

      flag = true;
      let verifiedAmount = 0;
      try {
        await config.flightSuretyApp.buy(firstAirline, flight, timestamp, {
          from: passenger,
          value: premium * config.weiMultiple,
        });
        verifiedAmount = await config.flightSuretyApp.getInsurance(
          firstAirline,
          flight,
          timestamp,
          { from: passenger }
        );
      } catch (e) {
        flag = false;
      }

      assert.equal(flag, true);
      assert.equal(verifiedAmount == premium * config.weiMultiple, true);
    });

    it("prevents a passenger from buying insurance for more than 1 ether", async () => {
      let firstAirline = accounts[1];
      let passenger = accounts[7];
      let flight = "ZA234";
      let timestamp = Math.floor(Date.now() / 1000);
      let premium = 1.5;

      flag = true;
      try {
        await config.flightSuretyApp.buy(firstAirline, flight, timestamp, {
          from: passenger,
          value: premium * config.weiMultiple,
        });
      } catch (e) {
        flag = false;
      }

      assert.equal(flag, false);
    });
  });
});
