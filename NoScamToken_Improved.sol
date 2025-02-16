
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract NoScamToken is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public constant MAX_SUPPLY = 100_000_000 * 10**18;
    uint256 public burnRate = 30; // Авто-сжигание (изменяется динамически)
    uint256 public constant MAX_HOLDING_PERCENT = 50; // 0.50% от общего предложения
    uint256 public constant MAX_SELL_PERCENT = 30; // Лимит продажи 30% от баланса за 24 часа
    uint256 public constant LIQUIDITY_LOCK_TIME = 365 days;
    uint256 public constant MAX_PRICE_INCREASE = 175; // Максимальный рост цены за 24 часа (175%)

    address public liquidityPool;
    uint256 public launchTime;
    uint256 public lastPrice;
    uint256 public lastPriceUpdate;
    uint256 public lockedLiquidityUntil;

    mapping(address => bool) private blacklist;
    mapping(address => uint256) private lastTrade;
    mapping(address => uint256) private lastSellTime;
    mapping(address => uint256) private dailySellLimit;
    mapping(address => uint256) private vestedBalance;
    mapping(address => uint256) private lastVestingClaim;

    event TokensBurned(uint256 amount);
    event TokensClaimed(address indexed user, uint256 amount);
    event AddedToBlacklist(address indexed user);
    event RemovedFromBlacklist(address indexed user);
    event LiquidityLocked(uint256 unlockTime);
    event BurnRateUpdated(uint256 newRate);
    event LiquidityWithdrawn(uint256 amount);
    event PriceUpdated(uint256 newPrice);

    modifier onlyWhitelisted() {
        require(block.timestamp >= launchTime, "Trading not yet started");
        _;
    }

    modifier liquidityLocked() {
        require(block.timestamp >= lockedLiquidityUntil, "Liquidity is locked");
        _;
    }

    constructor() ERC20("No Scam Token", "NST") {
        _mint(address(this), MAX_SUPPLY);
        launchTime = block.timestamp + 1 days;
        lockedLiquidityUntil = block.timestamp + LIQUIDITY_LOCK_TIME;
        emit LiquidityLocked(lockedLiquidityUntil);
    }

    function transfer(address recipient, uint256 amount) public override onlyWhitelisted returns (bool) {
        require(!blacklist[msg.sender], "Sender is blacklisted");
        require(balanceOf(recipient).add(amount) <= totalSupply().mul(MAX_HOLDING_PERCENT).div(10000), "Exceeds max holding");

        updateBurnRate();

        uint256 burnAmount = amount.mul(burnRate).div(100);
        uint256 transferAmount = amount.sub(burnAmount);

        _burn(msg.sender, burnAmount);
        _transfer(msg.sender, recipient, transferAmount);

        emit TokensBurned(burnAmount);
        return true;
    }

    function updateBurnRate() internal {
        uint256 volume = totalSupply().sub(balanceOf(address(this)));
        if (volume < totalSupply().div(50)) {
            burnRate = 40;
        } else if (volume > totalSupply().div(20)) {
            burnRate = 15;
        } else {
            burnRate = 30;
        }
        emit BurnRateUpdated(burnRate);
    }

    function addToBlacklist(address user) external onlyOwner {
        require(user != owner(), "Cannot blacklist contract owner");
        blacklist[user] = true;
        emit AddedToBlacklist(user);
    }

    function removeFromBlacklist(address user) external onlyOwner {
        blacklist[user] = false;
        emit RemovedFromBlacklist(user);
    }

    function updatePrice(uint256 newPrice) external onlyOwner {
        require(newPrice < lastPrice.mul(MAX_PRICE_INCREASE).div(100), "Price increase too high");
        if (newPrice >= lastPrice.mul(150).div(100) && block.timestamp < lastPriceUpdate + 1 days) {
            lockedLiquidityUntil = block.timestamp + 7 days;
        }
        lastPrice = newPrice;
        lastPriceUpdate = block.timestamp;
        emit PriceUpdated(newPrice);
    }

    function withdrawLiquidity() external onlyOwner liquidityLocked nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No liquidity to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");

        emit LiquidityWithdrawn(balance);
    }

    function renounceOwnership() public override onlyOwner {
        super.renounceOwnership();
    }
}
