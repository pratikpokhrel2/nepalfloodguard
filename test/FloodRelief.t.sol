// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FloodRelief} from "../contracts/FloodRelief.sol";

contract MockMaliciousNGO {
    FloodRelief public relief;
    uint256 public disasterId;
    bytes32 public targetHousehold;

    constructor(FloodRelief _relief) {
        relief = _relief;
    }

    function attack(uint256 _disasterId, bytes32 _household) external {
        disasterId = _disasterId;
        targetHousehold = _household;
    }

    receive() external payable {
        // Attempt reentrancy on receipt confirmation
        if (address(relief).balance >= msg.value) {
            try relief.confirmReceipt(disasterId, targetHousehold) {} catch {}
        }
    }
}

contract FloodReliefTest is Test {
    FloodRelief public relief;

    address public admin = address(0xAD);
    address public oracle = address(0x01);
    address public verifier = address(0x02);
    address public ngo = address(0x03);
    address public donor = address(0x04);
    address payable public treasury = payable(address(0x05));

    bytes32 public constant HOUSEHOLD_1 = keccak256("WARD_4_HOUSEHOLD_101");
    bytes32 public constant HOUSEHOLD_2 = keccak256("WARD_4_HOUSEHOLD_102");
    bytes32 public constant HOUSEHOLD_3 = keccak256("WARD_4_HOUSEHOLD_103");

    uint256 public disasterId;

    function setUp() public {
        vm.deal(admin, 100 ether);
        vm.deal(donor, 100 ether);

        vm.prank(admin);
        relief = new FloodRelief();

        vm.startPrank(admin);
        relief.setOracle(oracle, true);
        relief.setVerifier(verifier, true);
        relief.setNGO(ngo, true);
        disasterId = relief.createDisaster("Koshi Flash Flood 2026", 1 ether);
        vm.stopPrank();

        // Donor funds the disaster pool with 10 ETH
        vm.prank(donor);
        relief.donate{value: 10 ether}(disasterId);
    }

    function test_initialSetup() public view {
        assertEq(relief.admin(), admin);
        assertTrue(relief.isOracle(oracle));
        assertTrue(relief.isVerifier(verifier));
        assertTrue(relief.isNGO(ngo));
        assertEq(relief.available(disasterId), 10 ether);
    }

    function test_anchorAlert() public {
        bytes32 alertHash = keccak256("CRITICAL_WATER_LEVEL_SAPTARSHI_STATION_8");
        vm.prank(oracle);
        relief.anchorAlert(disasterId, alertHash);
    }

    function test_singleHouseholdFlow() public {
        // 1. Verifier registers household
        vm.prank(verifier);
        relief.registerHousehold(disasterId, HOUSEHOLD_1);

        // 2. Verifier confirms evacuation
        vm.prank(verifier);
        relief.confirmEvacuation(disasterId, HOUSEHOLD_1);

        // 3. NGO claims aid (0.5 ETH)
        vm.prank(ngo);
        relief.submitAidClaim(disasterId, HOUSEHOLD_1, 0.5 ether);

        assertEq(relief.available(disasterId), 9.5 ether);

        // 4. Verifier confirms receipt -> NGO receives ETH
        uint256 ngoPreBalance = ngo.balance;
        vm.prank(verifier);
        relief.confirmReceipt(disasterId, HOUSEHOLD_1);

        assertEq(ngo.balance, ngoPreBalance + 0.5 ether);
        assertEq(relief.available(disasterId), 9.5 ether);
    }

    function test_batchOperations() public {
        bytes32[] memory batch = new bytes32[](3);
        batch[0] = HOUSEHOLD_1;
        batch[1] = HOUSEHOLD_2;
        batch[2] = HOUSEHOLD_3;

        // Batch register
        vm.prank(verifier);
        relief.registerHouseholdsBatch(disasterId, batch);

        // Batch confirm evacuation
        vm.prank(verifier);
        relief.confirmEvacuationsBatch(disasterId, batch);

        // NGO submits claims
        vm.startPrank(ngo);
        relief.submitAidClaim(disasterId, HOUSEHOLD_1, 1 ether);
        relief.submitAidClaim(disasterId, HOUSEHOLD_2, 1 ether);
        relief.submitAidClaim(disasterId, HOUSEHOLD_3, 1 ether);
        vm.stopPrank();

        assertEq(relief.available(disasterId), 7 ether);

        // Batch confirm receipts
        uint256 ngoPreBalance = ngo.balance;
        vm.prank(verifier);
        relief.confirmReceiptsBatch(disasterId, batch);

        assertEq(ngo.balance, ngoPreBalance + 3 ether);
        assertEq(relief.available(disasterId), 7 ether);
    }

    function test_cancelAidClaim_UnlocksReservedFunds() public {
        vm.prank(verifier);
        relief.registerHousehold(disasterId, HOUSEHOLD_1);
        vm.prank(verifier);
        relief.confirmEvacuation(disasterId, HOUSEHOLD_1);

        // NGO claims
        vm.prank(ngo);
        relief.submitAidClaim(disasterId, HOUSEHOLD_1, 1 ether);
        assertEq(relief.available(disasterId), 9 ether);

        // NGO cancels claim due to logistics issue
        vm.prank(ngo);
        relief.cancelAidClaim(disasterId, HOUSEHOLD_1);

        // Funds are restored to available pool
        assertEq(relief.available(disasterId), 10 ether);

        // Household is now unblocked and can be claimed again
        vm.prank(ngo);
        relief.submitAidClaim(disasterId, HOUSEHOLD_1, 0.8 ether);
        assertEq(relief.available(disasterId), 9.2 ether);
    }

    function test_sweepRemainingFunds_AfterDisasterClosed() public {
        // Close disaster
        vm.prank(admin);
        relief.closeDisaster(disasterId);

        uint256 treasuryPreBalance = treasury.balance;
        vm.prank(admin);
        relief.sweepRemainingFunds(disasterId, treasury);

        assertEq(treasury.balance, treasuryPreBalance + 10 ether);
        assertEq(address(relief).balance, 0);
    }

    function test_revert_WhenDisasterNotActive() public {
        vm.prank(admin);
        relief.closeDisaster(disasterId);

        vm.expectRevert(FloodRelief.DisasterNotActive.selector);
        vm.prank(donor);
        relief.donate{value: 1 ether}(disasterId);
    }

    function test_revert_UnregisteredEvacuation() public {
        vm.expectRevert(FloodRelief.HouseholdNotRegistered.selector);
        vm.prank(verifier);
        relief.confirmEvacuation(disasterId, HOUSEHOLD_1);
    }

    function test_revert_UnauthorizedAdmin() public {
        vm.expectRevert(FloodRelief.NotAdmin.selector);
        vm.prank(donor);
        relief.createDisaster("Unauthorized", 1 ether);
    }
}
