//SPDX-License-Identifier: Unlicense
pragma solidity =0.7.6;
pragma abicoder v2;

// Openzepplin
import '@openzeppelin/contracts/access/Ownable.sol';

// uniswap 2 imports
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

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
    IUniswapV2Router02 public sushiSwapRouter;
    IUniswapV2Router02 public otherV2Router;
    ISwapRouter public v3SwapRouter;
    ISwapRouter public otherV3SwapRouter;
    address public v2Factory;
    address public sushiFactory;
    address public otherV2Factory;
    address public v3Factory;
    address public otherV3Factory;
    address public WETH9;

    // Structs and enums
    enum LPVersion { v2, oV2, v3, oV3, sushi }

    struct SwapInfo {
        address v2SwapRouter;
        address sushiSwapRouter;
        address otherV2Router;
        address v3SwapRouter;
        address otherV3SwapRouter;
        address v2Factory;
        address sushiFactory;
        address otherV2Factory;
        address v3Factory;
        address otherV3Factory;
        address WETH9;
    }

    struct PoolDesc {
        address token0;
        address token1;
        uint24 fee;
        LPVersion version;
    }

    struct FlashParams {
        uint256 loanAmnt;
        address loanToken;
        PoolDesc loanPool;
        PoolDesc[] poolPath;
    }

    struct FlashCallbackData {
        uint256 loanAmnt;
        address loanToken;
        address payer;
        PoolAddress.PoolKey poolKey;
        PoolDesc[] poolPath;
    }

    // Some Utility Functions here
    function constructCallbackParams(
        FlashParams memory params
    ) internal returns (FlashCallbackData memory) {
        return FlashCallbackData({
                    loanAmnt: params.loanAmnt,
                    loanToken: params.loanToken,
                    payer: msg.sender,
                    poolPath: params.poolPath,
                    poolKey: PoolAddress.PoolKey(address(0), address(0), 0)
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
        if (swapInfo.v2SwapRouter != address(0)) v2SwapRouter = IUniswapV2Router02(swapInfo.v2SwapRouter);
        if (swapInfo.sushiSwapRouter != address(0)) sushiSwapRouter = IUniswapV2Router02(swapInfo.sushiSwapRouter);
        if (swapInfo.otherV2Router != address(0)) otherV2Router = IUniswapV2Router02(swapInfo.otherV2Router);
        if (swapInfo.v3SwapRouter != address(0)) v3SwapRouter = ISwapRouter(swapInfo.v3SwapRouter);
        if (swapInfo.otherV3SwapRouter != address(0)) otherV3SwapRouter = ISwapRouter(swapInfo.otherV3SwapRouter);
        if (swapInfo.v2Factory != address(0)) v2Factory = swapInfo.v2Factory;
        if (swapInfo.sushiFactory != address(0)) sushiFactory = swapInfo.sushiFactory;
        if (swapInfo.otherV2Factory != address(0)) otherV2Factory = swapInfo.otherV2Factory;
        if (swapInfo.v3Factory != address(0)) v3Factory = swapInfo.v3Factory;
        if (swapInfo.otherV3Factory != address(0)) otherV3Factory = swapInfo.otherV3Factory;
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
        if (params.loanPool.version == LPVersion.v2) {
            startArbV2(params);
        } else if (params.loanPool.version == LPVersion.v3) {
            startArbV3(params);
        }

        // Do nothing if version not set.
    }

    function startArbV2(FlashParams memory params) internal {
        address token0 = params.loanPool.token0;
        address token1 = params.loanPool.token1;
        uint256 amount0 = params.loanToken == token0 ? params.loanAmnt : 0;
        uint256 amount1 = params.loanToken == token1 ? params.loanAmnt : 0;

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
        address token0 = params.loanPool.token0;
        address token1 = params.loanPool.token1;
        uint256 amount0 = params.loanToken == token0 ? params.loanAmnt : 0;
        uint256 amount1 = params.loanToken == token1 ? params.loanAmnt : 0;
        uint24 fee = params.loanPool.fee;

        // Get pool key
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee});
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(v3Factory, poolKey));

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
        PoolDesc memory tradePool,
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256) {
        uint256 amountOut = 0;
        if (tradePool.version == LPVersion.v2 || 
            tradePool.version == LPVersion.sushi ||
            tradePool.version == LPVersion.oV2) {
            amountOut = executeSwapV2(tradePool, amountIn, tokenIn, tokenOut);
        } else if (tradePool.version == LPVersion.v3 || tradePool.version == LPVersion.oV3) {
            amountOut = executeSwapV3(tradePool, amountIn, tokenIn, tokenOut);
        }
        return amountOut;
    }

    function executeSwapV2(
        PoolDesc memory tradePool,
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2Router02 routerInUse;
        address factoryInUse;
        if (tradePool.version == LPVersion.v2) {
            routerInUse = v2SwapRouter;
            factoryInUse = v2Factory;
        } else if (tradePool.version == LPVersion.sushi) {
            routerInUse = sushiSwapRouter;
            factoryInUse = sushiFactory;
        } else if (tradePool.version == LPVersion.oV2) {
            routerInUse = otherV2Router;
            factoryInUse = otherV2Factory;
        }

        TransferHelper.safeApprove(tokenIn, address(routerInUse), amountIn);

        // Calculate amount in and swap.
        uint deadline = block.timestamp + 200;
        uint amountRequired = UniswapV2Library.getAmountsOut(
            factoryInUse, 
            amountIn, 
            path
        )[0];
        uint amountReceived = routerInUse.swapExactTokensForTokens(
            amountIn, 
            amountRequired, 
            path, 
            address(this),
            deadline
        )[1];

        return amountReceived;
    }

    function executeSwapV3(
        PoolDesc memory tradePool,
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256) {
        ISwapRouter routerInUse;
        address factoryInUse;
        if (tradePool.version == LPVersion.v3) {
            routerInUse = v3SwapRouter;
            factoryInUse = v3Factory;
        } else if (tradePool.version == LPVersion.oV3) {
            routerInUse = otherV3SwapRouter;
            factoryInUse = otherV3Factory;
        }

        TransferHelper.safeApprove(tokenIn, address(routerInUse), amountIn);

        uint256 amountOut =
            routerInUse.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: tradePool.fee,
                    recipient: address(this),
                    deadline: block.timestamp + 200,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        
        return amountOut;
    }

    function executeTrades(FlashCallbackData memory params) internal returns (uint256, address) {
        uint pathLen = params.poolPath.length;
        uint256 amountToTrade = params.loanAmnt;
        address tokenIn = params.loanToken;
        address tokenOut = address(0);
        for (uint256 i = 0; i < pathLen; ++i) {
            PoolDesc memory poolDesc = params.poolPath[i];
            tokenOut = poolDesc.token0 == tokenIn ? poolDesc.token1 : poolDesc.token0;
            amountToTrade = executeSwap(poolDesc, amountToTrade, tokenIn, tokenOut);
            tokenIn = tokenOut;
        }  

        return (amountToTrade, tokenOut);
    }

    // Callback functions start here:
    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external override {
        // Decode call data and verify calling pool
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        assert(msg.sender == UniswapV2Library.pairFor(v2Factory, token0, token1));

        // calc fee
        uint fee = ((decoded.loanAmnt * 3) / 997) + 1;
        uint amountOwed = decoded.loanAmnt + fee;

        (uint256 amountOut, address tokenOut) = executeTrades(decoded);

        // if token is diff, recalc amount to repay
        if (tokenOut != decoded.loanToken) {
            address[] memory path = new address[](2);
            path[0] = tokenOut;
            path[1] = decoded.loanToken;
            amountOwed = UniswapV2Library.getAmountsIn(v2Factory, decoded.loanAmnt, path)[0];
        }
        // repay flash loan
        TransferHelper.safeApprove(tokenOut, address(this), amountOwed);
        TransferHelper.safeTransfer(tokenOut, decoded.payer, amountOwed);

        // if profitable pay profits to payer
        if (amountOut > amountOwed) {
            uint256 profit = LowGasSafeMath.sub(amountOut, amountOwed);

            TransferHelper.safeApprove(tokenOut, address(this), profit);
            TransferHelper.safeTransfer(tokenOut, decoded.payer, profit);
        }
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        // Decode call data and verify calling pool
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(v3Factory, decoded.poolKey);

        (uint256 amountOut, address tokenOut) = executeTrades(decoded);
        require(tokenOut == decoded.loanToken);

        // end up with amountOut0 of token0 from first swap and amountOut1 of token1 from second swap
        uint256 amountOwed = LowGasSafeMath.add(decoded.loanAmnt, LowGasSafeMath.add(fee0, fee1));

        TransferHelper.safeApprove(decoded.loanToken, address(this), amountOwed);
        TransferHelper.safeTransfer(decoded.loanToken, msg.sender, amountOwed);

        // if profitable pay profits to payer
        if (amountOut > amountOwed) {
            uint256 profit = LowGasSafeMath.sub(amountOut, amountOwed);

            TransferHelper.safeApprove(decoded.loanToken, address(this), profit);
            TransferHelper.safeTransfer(decoded.loanToken, decoded.payer, profit);
        }
    }
}
