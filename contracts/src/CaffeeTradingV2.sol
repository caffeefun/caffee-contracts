// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// H-1 FIX. A faithful copy of CaffeeTrading.sol's CaffeeCurve/CaffeeLaunch with ONE change:
// graduation adds liquidity only into a PRISTINE Uniswap pair, and defers (instead of
// reverting) if the pair was pre-seeded — blocking the pre-seed/donation theft proven in
// test/GraduationExploit.t.sol while keeping the curve live+tradeable and funds always safe.
// Everything else (quotes, params, ownership, predictToken) is unchanged so V2 is a drop-in
// (same LaunchToken bytecode -> vanity grinding unaffected; only the factory address changes).
import {LaunchToken, IERC20, IWETH, IUniV2Factory} from "./CaffeeTrading.sol";

interface IUniV2PairV2 {
    function mint(address to) external returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract CaffeeCurveV2 {
    address constant BURN = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable token;
    address public immutable creator;
    address public immutable treasury;
    IWETH public immutable weth;
    IUniV2Factory public immutable dexFactory;

    uint256 public immutable curveSupply;
    uint256 public immutable lpSupply;
    uint16 public immutable feeBps;

    uint256 public virtualTokenReserves;
    uint256 public virtualEthReserves;
    uint256 public realTokenReserves;
    uint256 public realEthReserves;
    bool public graduated;
    address public pair;

    uint256 private _lock;
    modifier lock() { require(_lock == 0, "REENTRANT"); _lock = 1; _; _lock = 0; }
    modifier live() { require(!graduated, "GRADUATED"); _; }

    event Buy(address indexed buyer, address indexed to, uint256 ethIn, uint256 tokensOut, uint256 refund);
    event Sell(address indexed seller, uint256 tokensIn, uint256 ethOut);
    event Graduated(address indexed pair, uint256 ethToLp, uint256 tokensToLp);
    event GraduationDeferred(address indexed pair); // pair not pristine — listing deferred, curve stays live

    constructor(address _token, address _creator, address _treasury, address _weth, address _dexFactory,
                uint256 _vToken, uint256 _vEth, uint256 _curveSupply, uint256 _lpSupply, uint16 _feeBps) {
        token = IERC20(_token); creator = _creator; treasury = _treasury;
        weth = IWETH(_weth); dexFactory = IUniV2Factory(_dexFactory);
        curveSupply = _curveSupply; lpSupply = _lpSupply; feeBps = _feeBps;
        virtualTokenReserves = _vToken; virtualEthReserves = _vEth;
        realTokenReserves = _curveSupply; realEthReserves = 0;
    }

    function buy(uint256 minTokensOut) external payable returns (uint256) { return _buy(msg.sender, minTokensOut); }
    function buyFor(address to, uint256 minTokensOut) external payable returns (uint256) { return _buy(to, minTokensOut); }

    function _buy(address to, uint256 minTokensOut) internal lock live returns (uint256 tokensOut) {
        require(msg.value > 0, "NO_ETH");
        uint256 gross = msg.value;
        uint256 ethIn = gross - (gross * feeBps) / 10000;
        tokensOut = (ethIn * virtualTokenReserves) / (virtualEthReserves + ethIn);
        uint256 fee;
        uint256 refund;
        if (tokensOut >= realTokenReserves) {
            tokensOut = realTokenReserves;
            ethIn = (virtualEthReserves * tokensOut) / (virtualTokenReserves - tokensOut);
            uint256 grossNeeded = (ethIn * 10000) / (10000 - feeBps);
            if (grossNeeded > gross) grossNeeded = gross;
            fee = grossNeeded - ethIn;
            refund = gross - grossNeeded;
        } else {
            fee = gross - ethIn;
        }
        require(tokensOut >= minTokensOut, "SLIPPAGE");
        virtualEthReserves += ethIn;
        virtualTokenReserves -= tokensOut;
        realEthReserves += ethIn;
        realTokenReserves -= tokensOut;
        require(token.transfer(to, tokensOut), "TOK_OUT");
        if (fee > 0) _sendEth(treasury, fee);
        if (refund > 0) _sendEth(msg.sender, refund);
        emit Buy(msg.sender, to, ethIn, tokensOut, refund);
        if (tokensOut > 0 && realTokenReserves == 0 && !graduated) _maybeGraduate();
    }

    function sell(uint256 tokenAmount, uint256 minEthOut) external lock live returns (uint256) {
        require(tokenAmount > 0, "NO_TOKENS");
        uint256 ethOut = (tokenAmount * virtualEthReserves) / (virtualTokenReserves + tokenAmount);
        require(ethOut <= realEthReserves, "INSUFFICIENT");
        uint256 fee = (ethOut * feeBps) / 10000;
        uint256 toUser = ethOut - fee;
        require(toUser >= minEthOut, "SLIPPAGE");
        virtualEthReserves -= ethOut;
        virtualTokenReserves += tokenAmount;
        realEthReserves -= ethOut;
        realTokenReserves += tokenAmount;
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "TOK_IN");
        if (fee > 0) _sendEth(treasury, fee);
        _sendEth(msg.sender, toUser);
        emit Sell(msg.sender, tokenAmount, toUser);
        return toUser;
    }

    /// Permissionless finalize: graduate a sold-out curve once its pair is pristine.
    function graduate() external lock live { require(realTokenReserves == 0, "NOT_SOLD_OUT"); _maybeGraduate(); }

    function _maybeGraduate() internal {
        address p = dexFactory.getPair(address(token), address(weth));
        if (p == address(0)) p = dexFactory.createPair(address(token), address(weth));
        // === H-1 FIX === add liquidity ONLY into a pristine pair; otherwise DEFER (don't
        // revert), leaving the curve live and the raised ETH untouched — nothing is ever
        // routed into an attacker's pre-seeded pool, so there is nothing to skim.
        if (IUniV2PairV2(p).totalSupply() != 0) { emit GraduationDeferred(p); return; }
        graduated = true;
        pair = p;
        uint256 ethForLp = realEthReserves;
        realEthReserves = 0;
        weth.deposit{value: ethForLp}();
        require(weth.transfer(p, ethForLp), "WETH_XFER");
        require(token.transfer(p, lpSupply), "TOK_LP");
        IUniV2PairV2(p).mint(BURN);
        emit Graduated(p, ethForLp, lpSupply);
    }

    function _sendEth(address to, uint256 amt) internal { (bool ok, ) = to.call{value: amt}(""); require(ok, "ETH_SEND"); }

    /* ---- views for the UI (unchanged from v1) ---- */
    function spotPrice() public view returns (uint256) { return virtualEthReserves * 1e18 / virtualTokenReserves; }
    function getBuyQuote(uint256 ethIn) external view returns (uint256 tokensOut) {
        uint256 net = ethIn - ethIn * feeBps / 10000;
        tokensOut = net * virtualTokenReserves / (virtualEthReserves + net);
        if (tokensOut > realTokenReserves) tokensOut = realTokenReserves;
    }
    function getSellQuote(uint256 tokenIn) external view returns (uint256 ethOut) {
        uint256 gross = tokenIn * virtualEthReserves / (virtualTokenReserves + tokenIn);
        ethOut = gross - gross * feeBps / 10000;
    }
    function tokensSold() external view returns (uint256) { return curveSupply - realTokenReserves; }
    receive() external payable { revert("NO_DIRECT_ETH"); }
}

contract CaffeeLaunchV2 {
    address public owner;
    address public treasury;
    uint16 public feeBps;
    IWETH public immutable weth;
    IUniV2Factory public immutable dexFactory;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant CURVE_SUPPLY = 800_000_000 ether;
    uint256 public constant LP_SUPPLY    = 200_000_000 ether;
    uint256 public virtualTokenInit = 1_073_000_000 ether;
    uint256 public virtualEthInit   = 1.2 ether;

    address[] public curves;
    mapping(address => address) public curveOf;

    event Launched(address indexed token, address indexed curve, address indexed creator, string name, string symbol);
    event ParamsUpdated(uint256 vToken, uint256 vEth, uint16 feeBps, address treasury);

    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }

    constructor(address _treasury, uint16 _feeBps, address _weth, address _dexFactory) {
        require(_feeBps <= 500, "FEE_TOO_HIGH");
        owner = msg.sender;
        treasury = _treasury == address(0) ? msg.sender : _treasury;
        feeBps = _feeBps;
        weth = IWETH(_weth);
        dexFactory = IUniV2Factory(_dexFactory);
    }

    function launch(string calldata name, string calldata symbol, bytes32 salt, uint256 minCreatorTokens)
        external payable returns (address token, address curve)
    {
        LaunchToken t = new LaunchToken{salt: salt}(name, symbol, 18, TOTAL_SUPPLY, address(this), false, false);
        CaffeeCurveV2 c = new CaffeeCurveV2(address(t), msg.sender, treasury, address(weth), address(dexFactory),
                                        virtualTokenInit, virtualEthInit, CURVE_SUPPLY, LP_SUPPLY, feeBps);
        require(t.transfer(address(c), TOTAL_SUPPLY), "SEED");
        t.renounceOwnership();
        if (msg.value > 0) c.buyFor{value: msg.value}(msg.sender, minCreatorTokens);
        curves.push(address(c));
        curveOf[address(t)] = address(c);
        emit Launched(address(t), address(c), msg.sender, name, symbol);
        return (address(t), address(c));
    }

    function predictToken(string calldata name, string calldata symbol, bytes32 salt) external view returns (address) {
        bytes memory init = abi.encodePacked(type(LaunchToken).creationCode,
            abi.encode(name, symbol, uint8(18), TOTAL_SUPPLY, address(this), false, false));
        bytes32 h = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(init)));
        return address(uint160(uint256(h)));
    }

    function curvesLength() external view returns (uint256) { return curves.length; }
    function setParams(uint256 _vToken, uint256 _vEth, uint16 _feeBps, address _treasury) external onlyOwner {
        require(_feeBps <= 500, "FEE_TOO_HIGH");
        virtualTokenInit = _vToken; virtualEthInit = _vEth; feeBps = _feeBps;
        treasury = _treasury == address(0) ? owner : _treasury;
        emit ParamsUpdated(_vToken, _vEth, _feeBps, treasury);
    }
    function transferOwnership(address n) external onlyOwner { require(n != address(0), "OWNER_ZERO"); owner = n; }
}
