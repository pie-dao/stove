// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.6;

import "../openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../openzeppelin-contracts/contracts/access/Ownable.sol";

import "./interfaces/IRecipe.sol";

/// @title The Stove
/// @author dantop114
/// @notice The Stove is used to join a PIE using funds from many users.
///         This enabled users to spend less gas fees.
contract Stove is Ownable {
    using SafeERC20 for IERC20;

    address public immutable tokenInput;
    address public immutable tokenOutput;
    address public recipe;
    address public feesRecipient;

    uint256 public constant MAX_FEE = 1e5; // max fees = 10%
    uint256 public epoch;
    uint256 public fees;

    mapping(address => bool) private bakers;

    mapping(uint256 => uint256) public totalDust;
    mapping(uint256 => uint256) public totalBaked;
    mapping(uint256 => uint256) public totalDeposits;
    mapping(address => uint256) public accountEpoch;
    mapping(uint256 => mapping(address => uint256)) public accountDeposits;
    mapping(uint256 => mapping(address => bool)) public accountClaimed;

    /// Users events

    event Deposit(
        address indexed account,
        uint256 indexed epoch,
        uint256 amount
    );

    event Withdraw(
        address indexed account,
        uint256 indexed epoch,
        uint256 amount
    );

    event WithdrawBaked(
        address indexed account,
        uint256 indexed epoch,
        uint256 amount
    );

    /// State changing events

    event Bake(
        address indexed baker,
        uint256 amountInput,
        uint256 amountOutput
    );

    event RecipeChanged(
        address indexed previousRecipe,
        address indexed newRecipe
    );

    event FeesRecipientChanged(
        address indexed oldFeesRecipient,
        address indexed newFeesRecipient
    );
    event FeesChanged(uint256 oldFees, uint256 newFees);

    event BakerAdded(address indexed addedBaker);
    event BakerRemoved(address indexed removedBaker);

    modifier onlyBakers() {
        require(bakers[msg.sender], "Not a baker!");
        _;
    }

    /// @dev _fees needs to be less than 1e5 (10% fees).
    ///      Fees are calculated as `percentage * 1e4`:
    ///
    ///      1% =>  10000
    ///      5% =>  50000
    ///     ... =>    ...
    constructor(
        address _tokenInput,
        address _tokenOutput,
        address _recipe,
        address _feesRecipient,
        uint256 _fees
    ) {
        require(_fees < MAX_FEE, "_fees > MAX_FEE");

        tokenInput = _tokenInput;
        tokenOutput = _tokenOutput;
        recipe = _recipe;
        fees = _fees;
        feesRecipient = _feesRecipient;

        IERC20(_tokenInput).safeApprove(_recipe, type(uint256).max);

        emit RecipeChanged(address(0), _recipe);
    }

    /// @notice The `deposit` function can be called to join the Stove and wait for the PIEs to be baked
    ///         The function accepts `amount` as a parameter and tries to transfer the amount given
    ///         by the user to this contract.
    /// @dev    If an user has already PIEs waiting to be withdrawn the function sends them to the user
    ///         and reinvests any dust left in the current epoch.
    function deposit(uint256 amount) external {
        IERC20(tokenInput).safeTransferFrom(msg.sender, address(this), amount);

        uint256 _epoch = epoch;

        if (
            accountEpoch[msg.sender] < _epoch &&
            !accountClaimed[_epoch][msg.sender]
        ) {
            amount += _withdrawBaked(msg.sender, true);
        }

        accountDeposits[_epoch][msg.sender] += amount;
        totalDeposits[_epoch] += amount;
        accountEpoch[msg.sender] = _epoch;

        emit Deposit(msg.sender, _epoch, amount);
    }

    /// @notice The `withdraw` function can be used in case the user can't wait
    ///         for the Stove to be activated.
    function withdraw(uint256 _amount) external {
        uint256 _epoch = epoch;

        accountDeposits[_epoch][msg.sender] -= _amount;
        totalDeposits[_epoch] -= _amount;

        IERC20(tokenInput).safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _epoch, _amount);
    }

    /// @notice The `withdrawBaked` function can be used to withdraw
    ///         the users' output PIEs.
    function withdrawBaked() external {
        _withdrawBaked(msg.sender, false);
    }

    /// @dev `_withdrawBaked` is an internal function used to withdraw users' funds.
    ///      If `reinvest` is true any dust belonging to the user trapped in an older epoch
    ///      is reinvested in the current epoch.
    function _withdrawBaked(address account, bool reinvest)
        internal
        returns (uint256 _dust)
    {
        uint256 _epoch = accountEpoch[account];
        require(!accountClaimed[_epoch][account], "Already claimed!");
        uint256 _userDeposits = accountDeposits[_epoch][account];
        require(_userDeposits > 0, "No deposits from the user!");
        uint256 _ratio = (_userDeposits * 1e18) / totalDeposits[_epoch];

        uint256 _bakedAmount = (totalBaked[_epoch] * _ratio) / 1e18;
        IERC20(tokenOutput).safeTransfer(account, _bakedAmount);

        if (totalDust[_epoch] > 0) {
            _dust = (totalDust[_epoch] * _ratio) / 1e18;
            if (!reinvest) IERC20(tokenInput).safeTransfer(account, _dust);
        }

        accountClaimed[_epoch][account] = true;

        emit WithdrawBaked(msg.sender, _epoch, _bakedAmount);
    }

    /// @notice The `bake` function is used to actually join the PIEs.
    function bake(
        uint256 _minOutput,
        uint256 _deadline,
        bytes calldata _data
    ) external onlyBakers {
        require(block.timestamp <= _deadline, "Deadline reached!");

        uint256 _epoch = epoch;
        uint256 _amountInput = totalDeposits[_epoch];

        uint256 _contractBalancePreBake = IERC20(tokenOutput).balanceOf(
            address(this)
        );

        (uint256 _usedInput, ) = IRecipe(recipe).bake(
            tokenInput,
            tokenOutput,
            _amountInput,
            _data
        );

        uint256 _contractBalanceAfterBake = IERC20(tokenOutput).balanceOf(
            address(this)
        );

        uint256 _bakedOutput = _contractBalanceAfterBake - _contractBalancePreBake;

        require(_bakedOutput >= _minOutput, "Insufficient baked amount!");

        emit Bake(msg.sender, _usedInput, _bakedOutput);

        uint256 _fees = fees;
        if (_fees > 0) {
            uint256 _feeAmount = (_bakedOutput * _fees) / 1e6;
            _bakedOutput -= _feeAmount;
            IERC20(tokenOutput).safeTransfer(feesRecipient, _feeAmount);
        }

        totalBaked[_epoch] = _bakedOutput;
        totalDust[_epoch] = _amountInput - _usedInput;

        epoch += 1;
    }

    /// @notice Utility function to check if an address is a baker or not.
    function isBaker(address who) external view returns (bool) {
        return bakers[who];
    }

    /// @notice Can be used to change the recipe called to join the PIE.
    function changeRecipe(address _recipe) external onlyOwner {
        recipe = _recipe;
    }

    /// @notice Can be used to change the fees percentage.
    function changeFees(uint256 _fees) external onlyOwner {
        require(_fees <= MAX_FEE, "_fees > MAX_FEE");

        emit FeesChanged(_fees, fees);

        fees = _fees;
    }

    /// @notice Can be used to change the fees recipient.
    function changeFeesRecipient(address _feesRecipient) external onlyOwner {
        emit FeesRecipientChanged(_feesRecipient, feesRecipient);

        feesRecipient = _feesRecipient;
    }

    /// @notice Can be used to add a baker.
    function addBaker(address baker) external onlyOwner {
        bakers[baker] = true;

        emit BakerAdded(baker);
    }

    /// @notice Can be used to remove a baker.
    function removeBaker(address baker) external onlyOwner {
        bakers[baker] = false;

        emit BakerRemoved(baker);
    }
}
