// SPDX-License-Identifier: GPL

// Copyright 2022 Fluidity Money. All rights reserved. Use of this
// source code is governed by a GPL-style license that can be found in the
// LICENSE.md file.

pragma solidity 0.8.16;
pragma abicoder v2;

import "../interfaces/IVEGovLockup.sol";
import "../interfaces/IERC20.sol";

import "./openzeppelin/SafeERC20.sol";

/// @dev MIN_LOCK_TIME to use as the min amount of time that BPT could
///      be locked
uint256 constant MIN_LOCK_TIME = 7 days;

/// @dev MAX_LOCK_TIME to use as the max amount of time that could be
///      locked up
uint256 constant MAX_LOCK_TIME = 365 days;

/// @dev FP_COEFFICIENT to use as the floating point coefficient
uint256 constant FP_COEFFICIENT = 1e18;

struct Lockup {
    uint256 lockTime;
    uint256 bptLocked;
    uint256 lockTimestamp;
}

contract VEGovLockup is IVEGovLockup {
    using SafeERC20 for IERC20;

    event LockCreated(address indexed spender, uint256 amount);

    event LockBPTIncreased(address indexed spender, uint256 extraBPT);

    event LockTimeIncreased(address indexed spender, uint256 extraTime);

    event LockWithdrew(address indexed spender, uint256 bptAmount);

    IERC20 private token_;

    mapping (address => uint) private locations_;

    Lockup[] private lockups_;

    uint256 tokenAmountDeposited_;

    constructor(IERC20 _token) {
        token_ = _token;

        // default immutable lockup value

        lockups_.push(Lockup({
            lockTime: 0,
            bptLocked: 0,
            lockTimestamp: 0
        }));
    }

    function findLockup(address _spender) internal view returns (Lockup memory) {
        return lockups_[locations_[_spender]];
    }

    function getLockTime(address _spender) public view returns (uint256) {
        return findLockup(_spender).lockTime;
    }

    function getBPTLocked(address _spender) public view returns (uint256) {
        return findLockup(_spender).bptLocked;
    }

    function getLockTimestamp(address _spender) public view returns (uint256) {
        return findLockup(_spender).lockTimestamp;
    }

    function minLockTime() public pure returns (uint256) {
        return MIN_LOCK_TIME;
    }

    function maxLockTime() public pure returns (uint256) {
        return MAX_LOCK_TIME;
    }

    function getVEFluidBalance(
        uint256 _bptLocked,
        uint256 _lockTime
    ) public pure returns (uint256) {
        return FP_COEFFICIENT * (_bptLocked * _lockTime) / MAX_LOCK_TIME;
    }

    /// @notice veFluidBalanceAtLock for the VE gov that the user receives at lock
    function getVEFluidBalanceAtLock(address _spender) public view returns (uint256) {
        return getVEFluidBalance(getBPTLocked(_spender), getLockTime(_spender));
    }

    function calcVEFluidDecayPerSecond(uint256 _bptLocked) public pure returns (uint256) {
        return FP_COEFFICIENT * _bptLocked / MAX_LOCK_TIME;
    }

    /// @notice veFluidDecayPerSecond to calculate how much VE Fluid you burn per second
    function getVEFluidDecayPerSecond(address _spender) public view returns (uint256) {
        return calcVEFluidDecayPerSecond(getBPTLocked(_spender));
    }

    function getSecondsSinceLock(address _spender) public view returns (uint256) {
        return block.timestamp - getLockTimestamp(_spender);
    }

    /**
     * @notice balanceOfCalc to use once the values have been
     *         discovered (for simulation)
     *
     * @param _veFluidBalanceAtLock available
     * @param _veFluidDecayPerSecond that VE Fluid is going down by
     * @param _lockTime that the lockup was created for
     * @param _secondsSinceLock as the time since the lockup was created
     *
     * @return VE Gov balance
     */
    function balanceOfCalc(
        uint256 _veFluidBalanceAtLock,
        uint256 _veFluidDecayPerSecond,
        uint256 _lockTime,
        uint256 _secondsSinceLock
    ) public pure returns (uint256) {
        if (_secondsSinceLock >= _lockTime) return 0;

        return _veFluidBalanceAtLock - (_veFluidDecayPerSecond * _secondsSinceLock);
    }

    /**
     * @notice balanceOfWith to determine balance of with the given inputs
     *
     * @param _bptLocked locked up
     * @param _lockTime that the amount was locked up for
     * @param _lockTimestamp that the lock was created at
     * @param _currentTimestamp as the current timestamp
     *
     * @return VE Gov balance
     */
     function balanceOfWith(
        uint256 _bptLocked,
        uint256 _lockTime,
        uint256 _lockTimestamp,
        uint256 _currentTimestamp
    ) public pure returns (uint256) {
        uint256 veFluidBalanceAtLock = getVEFluidBalance(_bptLocked, _lockTime);

        if (_currentTimestamp == _lockTimestamp) return veFluidBalanceAtLock;

        uint256 veFluidDecayPerSecond = calcVEFluidDecayPerSecond(_bptLocked);
        uint256 secondsSinceLock = _currentTimestamp - _lockTimestamp;

        return balanceOfCalc(
            veFluidBalanceAtLock,
            veFluidDecayPerSecond,
            _lockTime,
            secondsSinceLock
        );
    }

    /// @notice balanceOf the user's balance (the current VEFluid)
    function balanceOf(address _spender) public view returns (uint256) {
        return balanceOfWith(
            getBPTLocked(_spender),
            getLockTime(_spender),
            getLockTimestamp(_spender),
            block.timestamp
        );
    }

    function getLockExists(address _spender) public view returns (bool) {
        return findLockup(_spender).lockTime > 0;
    }

    /// @notice createLock for the user with the amount given (only one position!)
    function createLock(uint256 _amount, uint256 _lockTime) public {
        require(_amount > 0, "amount = 0");

        require(_lockTime + 1 > MIN_LOCK_TIME, "lock time too small");
        require(_lockTime - 1 < MAX_LOCK_TIME, "lock time too great");

        require(!getLockExists(msg.sender), "lock exists");

        emit LockCreated(msg.sender, _amount);

        tokenAmountDeposited_ += _amount;

        uint pos = lockups_.length;

        lockups_.push(Lockup({
            lockTime: _lockTime,
            bptLocked: _amount,
            lockTimestamp: block.timestamp
        }));

        locations_[msg.sender] = pos;

        bool rc = token_.transferFrom(msg.sender, address(this), _amount);

        require(rc, "failed to transfer");
    }

    function totalSupply() public view returns (uint256) {
        uint256 sum = 0;

        for (uint i = 0; i < lockups_.length; ++i)
            sum += balanceOfWith(
                lockups_[i].bptLocked,
                lockups_[i].lockTime,
                lockups_[i].lockTimestamp,
                block.timestamp
            );

        return sum;
    }

    function getRemainingLockTime(address _spender) public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;

        uint256 lockTimestamp = getLockTimestamp(_spender);

        uint256 lockTime = getLockTime(_spender);

        bool lockPeriodPassed = currentTimestamp - lockTimestamp > lockTime;

        if (lockPeriodPassed) {
            return 0;
        } else {
            return lockTime - (currentTimestamp - lockTimestamp);
        }
    }

    function extendLockTime(
        address _spender,
        uint256 _extraLockTime
    ) internal view returns (uint256) {
        return getRemainingLockTime(_spender) + _extraLockTime;
    }

    function _increaseBPTAmount(address _spender, uint256 _amount) internal {
        require(_amount > 0, "amount = 0");
        require(getLockExists(_spender), "lock doesn't exist");

        emit LockBPTIncreased(_spender, _amount);

        tokenAmountDeposited_ += _amount;

        uint256 newBPTLocked = getBPTLocked(_spender) + _amount;

        uint256 newLockTime = extendLockTime(_spender, 0);

        lockups_[locations_[_spender]] = Lockup({
            lockTime: newLockTime,
            bptLocked: newBPTLocked,
            lockTimestamp: block.timestamp
        });

        bool rc = token_.transferFrom(_spender, address(this), _amount);

        require(rc, "failed to transfer tokens");
    }

    /**
     * @notice increaseBPTAmount deposited in the current lockup
     *
     * @param _amount of BPT to increase the amount with
     */
    function increaseBPTAmount(uint256 _amount) public {
        _increaseBPTAmount(msg.sender, _amount);
    }

    function _increaseLockTime(address _spender, uint256 _extraLockTime) internal {
        require(_extraLockTime > 0, "extra lock time = 0");
        require(getLockExists(_spender), "lock doesn't exist");

        emit LockTimeIncreased(_spender, _extraLockTime);

        uint256 newLockTime = extendLockTime(_spender, _extraLockTime);

        require(newLockTime <= MAX_LOCK_TIME, "too long");

        lockups_[locations_[_spender]].lockTime = newLockTime;
        lockups_[locations_[_spender]].lockTimestamp = block.timestamp;
    }

    /**
     * @notice increaseLockTime of the current lockup
     *
     * @param _extraLockTime to increase the lock by
     */
     function increaseLockTime(uint256 _extraLockTime) public {
         _increaseLockTime(msg.sender, _extraLockTime);
     }

    function increaseLockTimeIncreaseAmount(uint256 _extraTime, uint256 _extraAmount) public {
        _increaseLockTime(msg.sender, _extraTime);
        _increaseBPTAmount(msg.sender, _extraAmount);
    }

    function hasLockExpired(address _spender) public view returns (bool) {
        // slither-disable-next-line incorrect-equality
        return balanceOf(_spender) == 0;
    }

    function disableLock(address _spender) internal {
        lockups_[locations_[_spender]] = Lockup({
            lockTime: 0,
            bptLocked: 0,
            lockTimestamp: 0
        });
    }

    /**
     * @notice withdraw the entire amount locked up once the lock has
     *         expired
     */
    function withdraw() public {
        require(getLockExists(msg.sender), "lock doesn't exist");
        require(hasLockExpired(msg.sender), "lock hasn't expired");

        uint256 bptLocked = getBPTLocked(msg.sender);

        emit LockWithdrew(msg.sender, bptLocked);

        tokenAmountDeposited_ -= bptLocked;

        disableLock(msg.sender);

        bool rc = token_.transfer(msg.sender, bptLocked);

        require(rc, "failed to transfer tokens out");
    }
}
