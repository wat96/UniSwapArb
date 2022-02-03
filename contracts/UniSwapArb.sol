//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

// Openzepplin
import '@openzeppelin/contracts/access/Ownable.sol';

// uniswap 2 imports
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';
import '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IERC20.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IWETH.sol';

// uniswap 3 imports
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol';
import '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
import '@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

/// @title Flash contract implementation
/// @notice An example contract using the Uniswap V3 flash function
contract PairFlash is IUniswapV2Callee, IUniswapV3FlashCallback, Ownable {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;

    // Constants and Constructors
    // Should be set or checked before use
    mapping(address => bool) private whitelist;
    IUniswapV2Router02 public v2SwapRouter;
    ISwapRouter public v3SwapRouter;
    address public v2Factory;
    address public v3Factory;
    address public WETH9;

    // Structs and enums
    enum UniswapVersion { v2, v3 }

    struct SwapInfo {
        address v2SwapRouter;
        address v3SwapRouter;
        address v2Factory;
        address v3Factory;
        address WETH9;
    }

    struct PoolDesc {
        address token0;
        address token1;
        uint24 fee;
        UniswapVersion version;
    }

    // pool 0 is desc for flash pool
    struct FlashParams {
        uint256 amount0;
        uint256 amount1;
        address token0;
        address token1;
        PoolDesc pool0;
        PoolDesc pool1;
    }

    struct FlashCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
        uint24 poolFee2;
        uint24 poolFee3;
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

    function constructCallbackParams(
        FlashParams memory params
    ) internal returns (FlashCallbackData memory) {
        return FlashCallbackData({
                    amount0: params.amount0,
                    amount1: params.amount1,
                    payer: msg.sender
                });
    }

    function constructCallbackParams(
        FlashParams memory params, 
        PoolAddress.PoolKey memory poolKey
    ) internal returns (FlashCallbackData memory) {
        FlashCallbackData memory res = constructCallbackParams(params);
        res.poolKey = poolKey;
        return res;
    }


    // Access Control stuff here
    function setSwapInfo(SwapInfo memory swapInfo) external onlyOwner {
        if (swapInfo.v2SwapRouter != address(0)) v2SwapRouter = swapInfo.v2SwapRouter;
        if (swapInfo.v3SwapRouter != address(0)) v3SwapRouter = swapInfo.v3SwapRouter;
        if (swapInfo.v2Factory != address(0)) v2Factory = swapInfo.v2Factory;
        if (swapInfo.v3Factory != address(0)) v3Factory = swapInfo.v3Factory;
        if (swapInfo.WETH9 != address(0)) WETH9 = swapInfo.WETH9;
    }

    function editWhitelist(address usr, bool allow) external onlyOwner {
        whitelist[usr] = allow;
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender] || msg.sender == owner());
        _;
    }

    // Entry functions here
    function startArb(FlashParams memory params) external onlyWhitelisted {
        // pool0 is flash pool, check what uniswap version
        if (params.pool0.version == UniswapVersion.v2) {
            startArbV2(params);
        } else if (params.pool0.version == UniswapVersion.v3) {
            startArbV3(params);
        }

        // Do nothing if version not set.
    }

    function startArbV2(FlashParams memory params) internal {
        address token0 = params.pool0.token0;
        address token1 = params.pool0.token1;
        uint256 amount0 = params.amount0;
        uint256 amount1 = params.amount1;

        // get pair addr and verify
        address pairAddress = IUniswapV2Factory(v2Factory).getPair(token0, token1); 
        require(pairAddress != address(0), 'Could not find pool on uniswap'); 

        // create flashloan 
        // bytes can not be empty or normal swap will happen
        IUniswapV2Pair(pairAddress).swap(
            amount0, 
            amount1, 
            address(this), 
            abi.encode(constructCallbackParams(params))
        );
    }

    function startArbV3(FlashParams memory params) internal {
        address token0 = params.pool0.token0;
        address token1 = params.pool0.token1;
        uint256 amount0 = params.amount0;
        uint256 amount1 = params.amount1;
        uint24 fee = params.pool0.fee;

        // Get pool key
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee});
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        // initiate flash on pool
        pool.flash(
            address(this),
            amount0,
            amount1,
            abi.encode(constructCallbackParams(params, poolKey))
        );
    }

    // Execute trade functions here:
    function executeSwap(

    ) internal {

    }

    // Callback functions start here:
    function uniswapV2Call(
        address sender, 
        uint amount0, 
        uint amount1, 
        bytes calldata data
    ) external override { 
        // Decode call data.
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        assert(msg.sender == UniswapV2Library.pairFor(v2Factory, token0, token1));
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(v3Factory, decoded.poolKey);

        address token0 = decoded.poolKey.token0;
        address token1 = decoded.poolKey.token1;

        TransferHelper.safeApprove(token0, address(swapRouter), decoded.amount0);
        TransferHelper.safeApprove(token1, address(swapRouter), decoded.amount1);

        // profitable check
        // exactInputSingle will fail if this amount not met
        uint256 amount1Min = LowGasSafeMath.add(decoded.amount1, fee1);
        uint256 amount0Min = LowGasSafeMath.add(decoded.amount0, fee0);

        // call exactInputSingle for swapping token1 for token0 in pool w/fee2
        uint256 amountOut0 =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: token1,
                    tokenOut: token0,
                    fee: decoded.poolFee2,
                    recipient: address(this),
                    deadline: block.timestamp + 200,
                    amountIn: decoded.amount1,
                    amountOutMinimum: amount0Min,
                    sqrtPriceLimitX96: 0
                })
            );

        // call exactInputSingle for swapping token0 for token 1 in pool w/fee3
        uint256 amountOut1 =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: token0,
                    tokenOut: token1,
                    fee: decoded.poolFee3,
                    recipient: address(this),
                    deadline: block.timestamp + 200,
                    amountIn: decoded.amount0,
                    amountOutMinimum: amount1Min,
                    sqrtPriceLimitX96: 0
                })
            );

        // end up with amountOut0 of token0 from first swap and amountOut1 of token1 from second swap
        uint256 amount0Owed = LowGasSafeMath.add(decoded.amount0, fee0);
        uint256 amount1Owed = LowGasSafeMath.add(decoded.amount1, fee1);

        TransferHelper.safeApprove(token0, address(this), amount0Owed);
        TransferHelper.safeApprove(token1, address(this), amount1Owed);

        if (amount0Owed > 0) pay(token0, address(this), msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(token1, address(this), msg.sender, amount1Owed);

        // if profitable pay profits to payer
        if (amountOut0 > amount0Owed) {
            uint256 profit0 = LowGasSafeMath.sub(amountOut0, amount0Owed);

            TransferHelper.safeApprove(token0, address(this), profit0);
            pay(token0, address(this), decoded.payer, profit0);
        }
        if (amountOut1 > amount1Owed) {
            uint256 profit1 = LowGasSafeMath.sub(amountOut1, amount1Owed);
            TransferHelper.safeApprove(token0, address(this), profit1);
            pay(token1, address(this), decoded.payer, profit1);
        }
    }
}
