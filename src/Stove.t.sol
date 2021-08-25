pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Stove.sol";

contract StoveTest is DSTest {
    Stove stove;

    function setUp() public {
        stove = new Stove();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
