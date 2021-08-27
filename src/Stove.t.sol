// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.6;

import "../openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "ds-test/test.sol";

import "./mocks/MockToken.sol";
import "./recipes/MockRecipe.sol";
import "./Stove.sol";

interface Hevm {
    function warp(uint256 x) external;
}

contract Account {
    function approve(address token, address who) external {
        IERC20(token).approve(who, type(uint256).max);
    }

    function deposit(Stove s, uint256 amount) external {
        s.deposit(amount);
    }

    function withdraw(Stove s, uint256 amount) external {
        s.withdraw(amount);
    }

    function withdrawBaked(Stove s) external {
        s.withdrawBaked();
    }
}

contract StoveTest is DSTest {
    Stove stove;

    MockToken tokenInput;
    MockToken tokenOutput;
    MockRecipe mockRecipe;

    address feesRecipient =
        address(0x00000000000000000000000000000000000000F3E5);

    function setUp() public {
        tokenInput = new MockToken("Input Token", "IN");
        tokenOutput = new MockToken("Output Token", "OUT");
        mockRecipe = new MockRecipe();

        stove = new Stove(
            address(tokenInput),
            address(tokenOutput),
            address(mockRecipe),
            feesRecipient,
            0
        );
    }

    function test_initial_state() public {
        assertEq(
            tokenInput.allowance(address(stove), address(mockRecipe)),
            type(uint256).max
        );

        // sanity check for initial state
        assertEq(stove.epoch(), 0);
    }

    function test_constructor() public {
        Stove s = new Stove(
            address(tokenInput),
            address(tokenOutput),
            address(mockRecipe),
            address(feesRecipient),
            0
        );

        assertEq(s.owner(), address(this));
        assertEq(s.tokenInput(), address(tokenInput));
        assertEq(s.tokenOutput(), address(tokenOutput));
        assertEq(s.recipe(), address(mockRecipe));
        assertEq(s.feesRecipient(), address(feesRecipient));
        assertEq(s.fees(), 0);
    }

    function testFail_constructor_exceeds_max_fee(uint256 _fees) public {
        if (_fees < 1e5) revert();

        Stove s = new Stove(
            address(1),
            address(2),
            address(3),
            address(4),
            _fees
        );

        s;
    }

    function test_fees() public {
        stove.changeFees(1e5);
        assertEq(stove.fees(), 1e5);
    }

    function test_fees_receiver() public {
        stove.changeFeesRecipient(address(1));
        assertEq(stove.feesRecipient(), address(1));
    }

    function testFail_fees_set(uint256 _fees) public {
        if (_fees < 1e5) revert();
        stove.changeFees(_fees);
    }

    function test_baker_is_setted() public {
        stove.addBaker(address(1));
        assertTrue(stove.isBaker(address(1)));
    }

    function test_baker_is_removed() public {
        stove.addBaker(address(1));
        assertTrue(stove.isBaker(address(1)));

        stove.removeBaker(address(1));
        assertTrue(!stove.isBaker(address(1)));
    }

    // address(this) is not a baker
    function testFail_baker_modifier() public {
        stove.bake(0, 0, "");
    }

    function test_change_recipe() public {
        stove.changeRecipe(address(1));
        assertEq(stove.recipe(), address(1));
    }

    // --- Functional tests

    function test_user_deposits(uint256 amount) public {
        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        assertEq(tokenInput.balanceOf(address(account)), 0);

        assertEq(stove.totalDeposits(0), amount);
        assertEq(stove.accountEpoch(address(account)), 0);
        assertEq(stove.accountDeposits(0, address(account)), amount);
    }

    function test_multiple_users_deposits(uint128 amountOne, uint128 amountTwo)
        public
    {
        unchecked {
            if ((amountOne + amountTwo) < amountOne) return;
            if ((amountOne + amountTwo) < amountTwo) return;
        }

        Account accountOne = new Account();
        Account accountTwo = new Account();

        tokenInput.mint(address(accountOne), amountOne);
        tokenInput.mint(address(accountTwo), amountTwo);

        accountOne.approve(address(tokenInput), address(stove));
        accountTwo.approve(address(tokenInput), address(stove));
        accountOne.deposit(stove, amountOne);
        accountTwo.deposit(stove, amountTwo);

        assertEq(stove.totalDeposits(0), amountOne + amountTwo);

        assertEq(tokenInput.balanceOf(address(accountOne)), 0);
        assertEq(stove.accountEpoch(address(accountOne)), 0);
        assertEq(stove.accountDeposits(0, address(accountOne)), amountOne);

        assertEq(tokenInput.balanceOf(address(accountTwo)), 0);
        assertEq(stove.accountEpoch(address(accountTwo)), 0);
        assertEq(stove.accountDeposits(0, address(accountTwo)), amountTwo);
    }

    function test_withdraw(uint256 amount) public {
        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);
        account.withdraw(stove, amount);

        assertEq(stove.totalDeposits(0), 0);
        assertEq(stove.accountDeposits(0, address(account)), 0);
        assertEq(tokenInput.balanceOf(address(account)), amount);
        assertEq(tokenInput.balanceOf(address(stove)), 0);
    }

    function test_withdraw_multiple_accounts(
        uint128 amountOne,
        uint128 amountTwo
    ) public {
        unchecked {
            if (amountOne == 0 || amountTwo == 0) return;
            if ((amountOne + amountTwo) < amountOne) return;
            if ((amountOne + amountTwo) < amountTwo) return;
        }

        Account accountOne = new Account();
        Account accountTwo = new Account();

        tokenInput.mint(address(accountOne), amountOne);
        tokenInput.mint(address(accountTwo), amountTwo);

        accountOne.approve(address(tokenInput), address(stove));
        accountTwo.approve(address(tokenInput), address(stove));
        accountOne.deposit(stove, amountOne);
        accountTwo.deposit(stove, amountTwo);

        accountOne.withdraw(stove, amountOne);
        assertEq(stove.totalDeposits(0), amountTwo);
        assertEq(stove.accountDeposits(0, address(accountOne)), 0);
        assertEq(tokenInput.balanceOf(address(accountOne)), amountOne);
        assertEq(tokenInput.balanceOf(address(stove)), amountTwo);
    }

    function testFail_double_withdraw(uint128 amountOne, uint128 amountTwo)
        public
    {
        unchecked {
            require(amountOne != 0 && amountTwo != 0);
            require((amountOne + amountTwo) > amountOne);
            require((amountOne + amountTwo) > amountTwo);
        }

        Account accountOne = new Account();
        Account accountTwo = new Account();

        tokenInput.mint(address(accountOne), amountOne);
        tokenInput.mint(address(accountTwo), amountTwo);

        accountOne.approve(address(tokenInput), address(stove));
        accountTwo.approve(address(tokenInput), address(stove));
        accountOne.deposit(stove, amountOne);
        accountTwo.deposit(stove, amountTwo);

        accountOne.withdraw(stove, amountOne);
        accountOne.withdraw(stove, amountTwo);
    }

    function test_bake(uint64 amount) public {
        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        assertEq(stove.epoch(), 1);
        assertEq(stove.totalBaked(0), amount);
        assertEq(tokenInput.balanceOf(address(stove)), 0);
        assertEq(tokenOutput.balanceOf(address(stove)), amount);
    }

    function testFail_bake_timeout(uint32 random_interval) public {
        stove.addBaker(address(this));
        uint256 deadline = block.timestamp;

        emit log_named_address("hevm_address", HEVM_ADDRESS);

        Hevm(HEVM_ADDRESS).warp(deadline + random_interval + 1);

        stove.bake(0, deadline, "");
    }

    function testFail_bake_fails_min_amount(uint64 amount) public {
        if (amount == 0) revert();

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        mockRecipe.setConversionRate(.5 ether);

        stove.addBaker(address(this));
        stove.bake(amount, block.timestamp, "");
    }

    function test_bake_user_withdraws_output(uint64 amount) public {
        if (amount == 0) return;

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        account.withdrawBaked(stove);

        assertEq(tokenOutput.balanceOf(address(account)), amount);
        assertEq(tokenOutput.balanceOf(address(stove)), 0);
    }

    function testFail_bake_user_withdraws_output_twice(uint64 amount) public {
        if (amount == 0) revert();

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        account.withdrawBaked(stove);
        account.withdrawBaked(stove);
    }

    function testFail_bake_user_withdraws_output_w_out_deposit(uint64 amount)
        public
    {
        if (amount == 0) revert();

        Account account = new Account();
        Account fakeAccount = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        fakeAccount.withdrawBaked(stove);
    }

    function test_bake_user_withdraws_output_not_exact_ratio(uint64 amount)
        public
    {
        if (amount == 0) return;

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        mockRecipe.setPercentageBaked(0.9 ether);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        require(tokenInput.balanceOf(address(stove)) > 0);
        uint256 _remainingAmount = tokenInput.balanceOf(address(stove));
        uint256 _bakedAmount = tokenOutput.balanceOf(address(stove));

        account.withdrawBaked(stove);

        assertEq(tokenInput.balanceOf(address(account)), _remainingAmount);
        assertEq(tokenOutput.balanceOf(address(account)), _bakedAmount);
        assertEq(tokenOutput.balanceOf(address(stove)), 0);
    }

    function test_bake_user_deposits_again(uint64 amount) public {
        if (amount == 0) return;

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        tokenInput.mint(address(account), amount);
        account.deposit(stove, amount);

        assertEq(stove.accountDeposits(1, address(account)), amount);
        assertEq(stove.totalDeposits(1), amount);
        assertEq(stove.accountEpoch(address(account)), 1);
        assertTrue(stove.accountClaimed(0, address(account)));

        assertEq(tokenOutput.balanceOf(address(account)), amount);
        assertEq(tokenOutput.balanceOf(address(stove)), 0);
    }

    function test_bake_user_deposits_again_not_exact_ratio(uint64 amount)
        public
    {
        if (amount == 0) return;

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        mockRecipe.setPercentageBaked(0.9 ether);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        require(tokenInput.balanceOf(address(stove)) > 0);
        uint256 _remainingAmount = tokenInput.balanceOf(address(stove));
        uint256 _bakedAmount = tokenOutput.balanceOf(address(stove));

        tokenInput.mint(address(account), amount);
        account.deposit(stove, amount);

        assertEq(
            stove.accountDeposits(1, address(account)),
            amount + _remainingAmount
        );

        assertEq(stove.totalDeposits(1), amount + _remainingAmount);
        assertEq(stove.accountEpoch(address(account)), 1);
        assertTrue(stove.accountClaimed(0, address(account)));

        assertEq(tokenOutput.balanceOf(address(account)), _bakedAmount);
        assertEq(tokenOutput.balanceOf(address(stove)), 0);
    }

    function testFail_bake_user_try_withdrawal(uint64 amount) public {
        require(amount != 0);

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        account.withdraw(stove, amount);
    }

    function test_baking_fees(uint64 amount, uint256 fees) public {
        if (amount == 0) return;
        if (fees > 1e5) return;

        Account account = new Account();

        tokenInput.mint(address(account), amount);

        account.approve(address(tokenInput), address(stove));
        account.deposit(stove, amount);

        stove.changeFees(fees);

        stove.addBaker(address(this));
        stove.bake(0, block.timestamp, "");

        uint256 _fees = (amount * fees) / 1e6;

        assertEq(tokenOutput.balanceOf(feesRecipient), _fees);
        assertEq(tokenOutput.balanceOf(address(stove)), amount - _fees);
    }
}
