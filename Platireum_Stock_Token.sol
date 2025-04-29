// * Important Notice: Terms of Use for Platireum Currency: By receiving this Platireum currency, you irrevocably acknowledge and solemnly pledge your full adherence to the subsequent terms and conditions:
// *  1- Platireum must not be used for fraud or deception.
// *  2- Platireum must not be used for lending or borrowing with interest (usury).
// *  3- Platireum must not be used to buy or sell intoxicants, narcotics, or anything that impairs judgment.
// *  4- Platireum must not be used for criminal activities and money laundering.
// *  5- Platireum must not be used for gambling.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title Fractional Stock Token
 * @notice ERC-20 compatible token representing fractional ownership of stocks
 * @dev Uses 18 decimal fixed-point arithmetic for fractional shares (like ETH wei)
 */
contract FractionalStockToken is IERC20, IERC20Metadata, AccessControl {
    using SafeMath for uint256;
    
    // Roles
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant STOCK_ISSUER_ROLE = keccak256("STOCK_ISSUER_ROLE");
    
    // Constants for fixed-point arithmetic
    uint256 public constant DECIMALS = 18;
    uint256 public constant ONE_SHARE = 10**DECIMALS; // 1.0 share in base units
    
    // Stock information structure
    struct Stock {
        string symbol;
        string companyName;
        uint256 totalShares; // In base units (10^18 units = 1 full share)
        uint256 price; // Price per FULL share in USD with 8 decimals
        uint256 lastUpdate;
        address priceFeed;
    }
    
    // Contract state
    Stock[] public stocks;
    mapping(uint256 => address) public stockIssuers;
    mapping(address => mapping(uint256 => uint256)) private _balances; // [user][stockId] => base units
    
    // ERC-20 metadata
    string private _name;
    string private _symbol;
    
    // Events
    event StockAdded(uint256 indexed stockId, string symbol, string companyName, address priceFeed);
    event PriceUpdated(uint256 indexed stockId, uint256 newPrice, uint256 timestamp);
    event SharesTransferred(address indexed from, address indexed to, uint256 stockId, uint256 amount);
    
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    // ERC-20 standard functions with fractional support
    function name() public view override returns (string memory) {
        return _name;
    }
    
    function symbol() public view override returns (string memory) {
        return _symbol;
    }
    
    function decimals() public view override returns (uint8) {
        return uint8(DECIMALS);
    }
    
    function totalSupply() public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < stocks.length; i++) {
            total = total.add(stocks[i].totalShares);
        }
        return total;
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < stocks.length; i++) {
            total = total.add(_balances[account][i]);
        }
        return total;
    }
    
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    
    // Not implemented for this example (would need approval logic)
    function allowance(address, address) public pure override returns (uint256) {
        return 0;
    }
    
    function approve(address, uint256) public pure override returns (bool) {
        revert("Approvals not implemented");
    }
    
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("TransferFrom not implemented");
    }
    
    // Stock-specific functions with fractional support
    function addStock(
        string memory symbol,
        string memory companyName,
        address priceFeed
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        uint256 stockId = stocks.length;
        stocks.push(Stock({
            symbol: symbol,
            companyName: companyName,
            totalShares: 0,
            price: 0,
            lastUpdate: 0,
            priceFeed: priceFeed
        }));
        stockIssuers[stockId] = msg.sender;
        emit StockAdded(stockId, symbol, companyName, priceFeed);
        return stockId;
    }
    
    function updateStockPrice(uint256 stockId) public onlyRole(ORACLE_UPDATER_ROLE) {
        require(stockId < stocks.length, "Invalid stock ID");
        AggregatorV3Interface priceFeed = AggregatorV3Interface(stocks[stockId].priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        stocks[stockId].price = uint256(price);
        stocks[stockId].lastUpdate = block.timestamp;
        emit PriceUpdated(stockId, uint256(price), block.timestamp);
    }
    
    /**
     * @dev Mints fractional shares (amount in base units)
     * @param to The recipient address
     * @param stockId The stock identifier
     * @param amount The amount in base units (10^18 units = 1 full share)
     */
    function mintShares(
        address to,
        uint256 stockId,
        uint256 amount
    ) public onlyRole(STOCK_ISSUER_ROLE) {
        require(stockId < stocks.length, "Invalid stock ID");
        require(to != address(0), "Mint to zero address");
        
        stocks[stockId].totalShares = stocks[stockId].totalShares.add(amount);
        _balances[to][stockId] = _balances[to][stockId].add(amount);
        
        emit SharesTransferred(address(0), to, stockId, amount);
    }
    
    /**
     * @dev Burns fractional shares (amount in base units)
     * @param from The address to burn from
     * @param stockId The stock identifier
     * @param amount The amount in base units (10^18 units = 1 full share)
     */
    function burnShares(
        address from,
        uint256 stockId,
        uint256 amount
    ) public onlyRole(STOCK_ISSUER_ROLE) {
        require(stockId < stocks.length, "Invalid stock ID");
        require(_balances[from][stockId] >= amount, "Insufficient balance");
        
        stocks[stockId].totalShares = stocks[stockId].totalShares.sub(amount);
        _balances[from][stockId] = _balances[from][stockId].sub(amount);
        
        emit SharesTransferred(from, address(0), stockId, amount);
    }
    
    /**
     * @dev Transfers fractional shares between accounts
     * @param stockId The stock identifier
     * @param amount The amount in base units (10^18 units = 1 full share)
     */
    function transferShares(
        address to,
        uint256 stockId,
        uint256 amount
    ) public {
        require(stockId < stocks.length, "Invalid stock ID");
        require(_balances[msg.sender][stockId] >= amount, "Insufficient balance");
        require(to != address(0), "Transfer to zero address");
        
        _balances[msg.sender][stockId] = _balances[msg.sender][stockId].sub(amount);
        _balances[to][stockId] = _balances[to][stockId].add(amount);
        
        emit SharesTransferred(msg.sender, to, stockId, amount);
    }
    
    // Internal transfer function with proportional distribution
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(recipient != address(0), "Transfer to zero address");
        require(balanceOf(sender) >= amount, "Insufficient balance");
        
        uint256 remaining = amount;
        
        // Iterate through all stocks to transfer proportionally
        for (uint256 i = 0; i < stocks.length && remaining > 0; i++) {
            uint256 balance = _balances[sender][i];
            if (balance == 0) continue;
            
            // Calculate proportional amount to transfer
            uint256 transferAmount = amount.mul(balance).div(balanceOf(sender));
            if (transferAmount > remaining) {
                transferAmount = remaining;
            }
            if (transferAmount > balance) {
                transferAmount = balance;
            }
            
            if (transferAmount > 0) {
                _balances[sender][i] = _balances[sender][i].sub(transferAmount);
                _balances[recipient][i] = _balances[recipient][i].add(transferAmount);
                remaining = remaining.sub(transferAmount);
                
                emit SharesTransferred(sender, recipient, i, transferAmount);
            }
        }
    }
    
    // View functions with fractional support
    function getStockInfo(uint256 stockId) public view returns (Stock memory) {
        require(stockId < stocks.length, "Invalid stock ID");
        return stocks[stockId];
    }
    
    function getShareBalance(address account, uint256 stockId) public view returns (uint256) {
        require(stockId < stocks.length, "Invalid stock ID");
        return _balances[account][stockId];
    }
    
    /**
     * @dev Converts base units to full shares with decimals
     * @param baseUnits Amount in base units (10^18 = 1.0 share)
     * @return Full shares with decimal places
     */
    function toFullShares(uint256 baseUnits) public pure returns (uint256) {
        return baseUnits.div(ONE_SHARE);
    }
    
    /**
     * @dev Converts full shares to base units
     * @param fullShares Amount in full shares (1.5 shares = 1.5 * 10^18 units)
     * @return Base units representation
     */
    function toBaseUnits(uint256 fullShares) public pure returns (uint256) {
        return fullShares.mul(ONE_SHARE);
    }
}