// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IFeeSharingSystem {
    function deposit(uint256 amount, bool claimRewardToken) external;
    function harvest() external;
    function withdraw(uint256 amount, bool claimRewardToken) external;
}
