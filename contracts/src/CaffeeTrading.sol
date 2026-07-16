// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*
 * Caffee trading — pump.fun-style bonding curve + fair launch, graduating to the
 * live Uniswap-V2 DEX on Robinhood Chain.
 *
 *  LaunchToken  : fixed-supply ERC-20 (reused from the launchpad).
 *  CaffeeCurve  : holds the whole supply; buy()/sell() on a virtual-reserve
 *                 constant-product curve with a platform fee; graduates to a
 *                 Uniswap-V2 WETH pair (liquidity locked) when the curve sells out.
 *  CaffeeLaunch : factory — deploys token (CREATE2, vanity-able) + curve with
 *                 pump.fun default params and seeds the supply.
 *
 * Defaults (owner-tunable on the factory):
 *   total supply      1,000,000,000
 *   for the curve       800,000,000  (sold via buys)
 *   for graduation LP   200,000,000  (added to the DEX pair, LP burned)
 *   virtual token res 1,073,000,000  virtual ETH res 1.2   fee 1%
 *   -> selling out the curve raises ~3.5 ETH, which all becomes locked LP.
 */

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}
interface IWETH is IERC20 { function deposit() external payable; }
interface IUniV2Factory {
    function getPair(address, address) external view returns (address);
    function createPair(address, address) external returns (address);
}
interface IUniV2Pair { function mint(address to) external returns (uint256); }

/* ----------------------------- LaunchToken ----------------------------- */
contract LaunchToken is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    address public owner;
    bool public immutable mintable;
    bool public immutable burnable;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialSupply, address _owner, bool _mintable, bool _burnable) {
        require(_owner != address(0), "OWNER_ZERO");
        name = _name; symbol = _symbol; decimals = _decimals; owner = _owner; mintable = _mintable; burnable = _burnable;
        if (_initialSupply > 0) { _totalSupply = _initialSupply; _balances[_owner] = _initialSupply; emit Transfer(address(0), _owner, _initialSupply); }
        emit OwnershipTransferred(address(0), _owner);
    }
    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view returns (uint256) { return _balances[a]; }
    function allowance(address o, address s) external view returns (uint256) { return _allowances[o][s]; }
    function transfer(address to, uint256 amt) external returns (bool) { _transfer(msg.sender, to, amt); return true; }
    function approve(address sp, uint256 amt) external returns (bool) { _allowances[msg.sender][sp] = amt; emit Approval(msg.sender, sp, amt); return true; }
    function transferFrom(address f, address to, uint256 amt) external returns (bool) {
        uint256 a = _allowances[f][msg.sender];
        if (a != type(uint256).max) { require(a >= amt, "ALLOWANCE"); _allowances[f][msg.sender] = a - amt; emit Approval(f, msg.sender, a - amt); }
        _transfer(f, to, amt); return true;
    }
    function _transfer(address f, address to, uint256 amt) internal {
        require(to != address(0), "TO_ZERO");
        uint256 b = _balances[f]; require(b >= amt, "BALANCE");
        unchecked { _balances[f] = b - amt; _balances[to] += amt; }
        emit Transfer(f, to, amt);
    }
    function mint(address to, uint256 amt) external onlyOwner { require(mintable, "NOT_MINTABLE"); require(to != address(0), "TO_ZERO"); _totalSupply += amt; unchecked { _balances[to] += amt; } emit Transfer(address(0), to, amt); }
    function burn(uint256 amt) external { require(burnable, "NOT_BURNABLE"); uint256 b = _balances[msg.sender]; require(b >= amt, "BALANCE"); unchecked { _balances[msg.sender] = b - amt; _totalSupply -= amt; } emit Transfer(msg.sender, address(0), amt); }
    function transferOwnership(address n) external onlyOwner { require(n != address(0), "OWNER_ZERO"); emit OwnershipTransferred(owner, n); owner = n; }
    function renounceOwnership() external onlyOwner { emit OwnershipTransferred(owner, address(0)); owner = address(0); }
}

/* ----------------------------- CaffeeCurve ----------------------------- */
contract CaffeeCurve {
    address constant BURN = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable token;
    address public immutable creator;
    address public immutable treasury;
    IWETH public immutable weth;
    IUniV2Factory public immutable dexFactory;

    uint256 public immutable curveSupply; // sellable tokens
    uint256 public immutable lpSupply;     // tokens reserved for graduation LP
    uint16 public immutable feeBps;

    uint256 public virtualTokenReserves;
    uint256 public virtualEthReserves;
    uint256 public realTokenReserves;      // sellable remaining
    uint256 public realEthReserves;        // ETH collected (net of fees), == contract balance
    bool public graduated;
    address public pair;

    uint256 private _lock;
    modifier lock() { require(_lock == 0, "REENTRANT"); _lock = 1; _; _lock = 0; }
    modifier live() { require(!graduated, "GRADUATED"); _; }

    event Buy(address indexed buyer, address indexed to, uint256 ethIn, uint256 tokensOut, uint256 refund);
    event Sell(address indexed seller, uint256 tokensIn, uint256 ethOut);
    event Graduated(address indexed pair, uint256 ethToLp, uint256 tokensToLp);

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
            // final buy — sell exactly the remaining curve supply, refund the excess
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
        // effects
        virtualEthReserves += ethIn;
        virtualTokenReserves -= tokensOut;
        realEthReserves += ethIn;
        realTokenReserves -= tokensOut;
        // interactions
        require(token.transfer(to, tokensOut), "TOK_OUT");
        if (fee > 0) _sendEth(treasury, fee);
        if (refund > 0) _sendEth(msg.sender, refund);
        emit Buy(msg.sender, to, ethIn, tokensOut, refund);
        if (realTokenReserves == 0) _graduate();
    }

    function sell(uint256 tokenAmount, uint256 minEthOut) external lock live returns (uint256) {
        require(tokenAmount > 0, "NO_TOKENS");
        uint256 ethOut = (tokenAmount * virtualEthReserves) / (virtualTokenReserves + tokenAmount);
        require(ethOut <= realEthReserves, "INSUFFICIENT");
        uint256 fee = (ethOut * feeBps) / 10000;
        uint256 toUser = ethOut - fee;
        require(toUser >= minEthOut, "SLIPPAGE");
        // effects
        virtualEthReserves -= ethOut;
        virtualTokenReserves += tokenAmount;
        realEthReserves -= ethOut;
        realTokenReserves += tokenAmount;
        // interactions
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "TOK_IN");
        if (fee > 0) _sendEth(treasury, fee);
        _sendEth(msg.sender, toUser);
        emit Sell(msg.sender, tokenAmount, toUser);
        return toUser;
    }

    function _graduate() internal {
        graduated = true;
        address p = dexFactory.getPair(address(token), address(weth));
        if (p == address(0)) p = dexFactory.createPair(address(token), address(weth));
        pair = p;
        uint256 ethForLp = realEthReserves;
        realEthReserves = 0;
        weth.deposit{value: ethForLp}();
        require(weth.transfer(p, ethForLp), "WETH_XFER");
        require(token.transfer(p, lpSupply), "TOK_LP");
        IUniV2Pair(p).mint(BURN); // LP tokens locked forever
        emit Graduated(p, ethForLp, lpSupply);
    }

    function _sendEth(address to, uint256 amt) internal { (bool ok, ) = to.call{value: amt}(""); require(ok, "ETH_SEND"); }

    /* ---- views for the UI ---- */
    function spotPrice() public view returns (uint256) { return virtualEthReserves * 1e18 / virtualTokenReserves; } // wei per token
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

/* ----------------------------- CaffeeLaunch ---------------------------- */
contract CaffeeLaunch {
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
    mapping(address => address) public curveOf; // token => curve

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

    /// Deploy a fair-launch token (CREATE2 via `salt`, so the address can be vanity-ground)
    /// + its bonding curve, seeded with the whole supply. Optional dev-buy with msg.value.
    function launch(string calldata name, string calldata symbol, bytes32 salt, uint256 minCreatorTokens)
        external payable returns (address token, address curve)
    {
        LaunchToken t = new LaunchToken{salt: salt}(name, symbol, 18, TOTAL_SUPPLY, address(this), false, false);
        CaffeeCurve c = new CaffeeCurve(address(t), msg.sender, treasury, address(weth), address(dexFactory),
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
