//SPDX-License-Identifier: Unlicense
pragma solidity =0.7.6;
pragma abicoder v2;

import "hardhat/console.sol";

// uniswap 3 imports
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol';
import '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
import '@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol';

// looks rare
import { IFeeSharingSystem } from './IFeeSharingSystem.sol';

/// @title Flash contract implementation
/// @notice An example contract using the Uniswap V3 flash function
contract UniSwapArb is IUniswapV3FlashCallback {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;

    // Constants and Constructors
    // Should be set or checked before use
    ISwapRouter public immutable swapRouter;
    address public immutable v3Factory;
    address public immutable WETH9;
    address public immutable LOOKS;
    IFeeSharingSystem public immutable feeSharing;

    constructor(
        ISwapRouter _swapRouter,
        address _v3Factory,
        address _WETH9,
        address _LOOKS,
        address _LOOKS_FEE_SHARING
    ) public {
        swapRouter = _swapRouter;
        v3Factory = _v3Factory;
        WETH9 = _WETH9;
        LOOKS = _LOOKS;
        feeSharing = IFeeSharingSystem(_LOOKS_FEE_SHARING);
    }

    struct FlashCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
        uint24 fee;
    }

    // Entry functions here
    function startArb(uint256 amount1) external {
        console.log("Entering arb");
        uint24 fee = 3000;
        uint256 amount0 = 0;
        address token1 = LOOKS;
        address token0 = WETH9;

        // Get pool key
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee});
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(v3Factory, poolKey));
        console.log(PoolAddress.computeAddress(v3Factory, poolKey));

        // initiate flash on pool
        pool.flash(
            address(this),
            amount0,
            amount1,
            abi.encode(
                FlashCallbackData({
                    amount0: amount0,
                    amount1: amount1,
                    payer: msg.sender,
                    poolKey: poolKey,
                    fee: fee
                })
            )
        );
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(v3Factory, decoded.poolKey);
        console.log("Entering flash");

        // get weth balance before
        uint256 wethBal0 = IWETH9(WETH9).balanceOf(address(this));

        // DO deposit, then harvest, then withdraw
        TransferHelper.safeApprove(LOOKS, address(feeSharing), decoded.amount1);
        console.log(decoded.amount1);
        feeSharing.deposit(decoded.amount1, false);
        feeSharing.harvest();
        feeSharing.withdraw(decoded.amount1, false);

        // get weth balance after and calc diff
        uint256 wethBal1 = IWETH9(WETH9).balanceOf(address(this));
        uint256 wethBalDiff = LowGasSafeMath.sub(wethBal1, wethBal0);
        console.log(wethBalDiff);

        uint256 owed = fee1;

        // make swap to cover fee
        TransferHelper.safeApprove(WETH9, address(swapRouter), wethBalDiff);
        uint256 amountOut =
            swapRouter.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: WETH9,
                    tokenOut: LOOKS,
                    fee: decoded.fee,
                    recipient: address(this),
                    deadline: block.timestamp + 200,
                    amountOut: fee0,
                    amountInMaximum: wethBalDiff,
                    sqrtPriceLimitX96: 0
                })
            );

        uint256 amountOwed = LowGasSafeMath.add(decoded.amount1, owed);
        TransferHelper.safeApprove(LOOKS, address(this), amountOwed);
        if (amountOwed > 0) pay(LOOKS, address(this), msg.sender, amountOwed);

        // if profitable pay profits to payer
        uint256 wethBal2 = IWETH9(WETH9).balanceOf(address(this));
        if (wethBal2 > 0) {
            TransferHelper.safeApprove(WETH9, address(this), wethBal2);
            pay(WETH9, address(this), decoded.payer, wethBal2);
        }
    }

    // Some Utility Functions here
    // pay function to make sending token easier
    function pay (
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
