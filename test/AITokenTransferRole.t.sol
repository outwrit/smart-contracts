// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../src/AITokenTransferRole.sol"; // Adjust the path as needed

contract AITokenTransferRoleTest is Test {
    AITokenTransferRole token;

    address admin = address(0xAA);
    address minter = address(0xBB);
    address burner = address(0xCC);
    address xferer = address(0xDD);
    address alice = address(0x1111);
    address bob = address(0x2222);

    // Replicate OZ's EIP-2612 typehash:
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        vm.startPrank(admin);
        token = new AITokenTransferRole("AIToken", "AIT");
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        token.grantRole(token.TRANSFER_ROLE(), xferer);
        vm.stopPrank();
    }

    function testMint() public {
        vm.prank(minter);
        token.mint(alice, 1000);
        assertEq(token.balanceOf(alice), 1000);
    }

    function testFailMintWithoutRole() public {
        token.mint(alice, 1000); // Should revert: caller lacks MINTER_ROLE
    }

    function testBurn() public {
        vm.startPrank(minter);
        token.mint(alice, 500);
        vm.stopPrank();

        vm.prank(burner);
        token.burn(alice, 200);
        assertEq(token.balanceOf(alice), 300);
    }

    function testFailBurnWithoutRole() public {
        vm.startPrank(minter);
        token.mint(alice, 500);
        vm.stopPrank();

        // Caller lacks BURNER_ROLE
        token.burn(alice, 200);
    }

    function testTransfer() public {
        vm.startPrank(minter);
        token.mint(xferer, 1000);
        vm.stopPrank();

        vm.prank(xferer);
        token.transfer(alice, 500);
        assertEq(token.balanceOf(xferer), 500);
        assertEq(token.balanceOf(alice), 500);
    }

    function testFailTransferWithoutRole() public {
        vm.startPrank(minter);
        token.mint(alice, 500);
        vm.stopPrank();

        // Alice does not have TRANSFER_ROLE
        vm.prank(alice);
        token.transfer(bob, 100);
    }

    function testTransferFrom() public {
        vm.startPrank(minter);
        token.mint(xferer, 1000);
        vm.stopPrank();

        vm.startPrank(xferer);
        token.approve(xferer, 1000);
        token.transferFrom(xferer, alice, 400);
        vm.stopPrank();

        assertEq(token.balanceOf(xferer), 600);
        assertEq(token.balanceOf(alice), 400);
    }

    function testFailTransferFromWithoutRole() public {
        vm.startPrank(minter);
        token.mint(alice, 500);
        vm.stopPrank();

        // Alice lacks TRANSFER_ROLE
        vm.prank(alice);
        token.approve(alice, 200);
        vm.prank(alice);
        token.transferFrom(alice, bob, 200);
    }

    function testGrantAndRevokeTransferRole() public {
        address someUser = address(0x99);

        vm.prank(admin);
        token.approveTransferAddress(someUser);
        assertTrue(token.hasRole(token.TRANSFER_ROLE(), someUser));

        vm.prank(admin);
        token.revokeTransferAddress(someUser);
        assertFalse(token.hasRole(token.TRANSFER_ROLE(), someUser));
    }

    function testPermit() public {
        // We give an address TRANSFER_ROLE so it can call permit
        uint256 privateKey = 0x123456789ABCDEF;
        address signer = vm.addr(privateKey);

        vm.startPrank(admin);
        token.grantRole(token.TRANSFER_ROLE(), signer);
        vm.stopPrank();

        // Mint tokens to signer
        vm.prank(minter);
        token.mint(signer, 500);

        // Prepare permit data
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = token.nonces(signer);

        // Compute the EIP712 message hash
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, signer, bob, 200, nonce, deadline));
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // signer calls permit
        vm.prank(signer);
        token.permit(signer, bob, 200, deadline, v, r, s);
        assertEq(token.allowance(signer, bob), 200);
    }

    function testPermitRevertUnapproved() public {
        // We give an address TRANSFER_ROLE so it can call permit
        uint256 privateKey = 0x123456789ABCDEF;
        address signer = vm.addr(privateKey);
        vm.startPrank(admin);
        // Don't grant TRANSFER_ROLE to simulate unauthorized access
        vm.stopPrank();

        // Mint tokens to signer
        vm.prank(minter);
        token.mint(signer, 500);

        // Prepare permit data
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = token.nonces(signer);

        // Compute the EIP712 message hash
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, signer, bob, 200, nonce, deadline));
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Should revert because signer doesn't have TRANSFER_ROLE
        vm.expectRevert();
        vm.prank(signer);
        token.permit(signer, bob, 200, deadline, v, r, s);
    }
}
