// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Launchpad {
    struct TokenSale {
        address tokenAddress;
        address owner;
        uint256 price;
        uint256 amountForSale;
        uint256 sold;
        bool isActive;
        bool isPrivate;
    }

    address public admin;
    mapping(address => TokenSale) public tokenSales;
    address[] public listedTokens;

    event TokenListed(address indexed token, address indexed owner, uint256 price, uint256 amount);
    event TokenBought(address indexed buyer, address indexed token, uint256 amount, uint256 cost);
    event SaleUpdated(address indexed token, bool isActive, uint256 price);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Hanya Admin yang bisa melakukan ini");
        _;
    }

    modifier saleExists(address token) {
        require(tokenSales[token].tokenAddress != address(0), "Penjualan belum tersedia");
        _;
    }

    modifier onlySaleOwner(address token) {
        require(tokenSales[token].owner == msg.sender, "Bukan Penjual");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function listToken(
        address _tokenAddress,
        uint256 _price,
        uint256 _amountForSale,
        bool _isPrivate
    ) external {
        require(_price > 0, "Harga lebih besar dari 0");
        require(_amountForSale > 0, "Jumlah harus lebih besar dari 0");

        IERC20 token = IERC20(_tokenAddress);
        require(token.transferFrom(msg.sender, address(this), _amountForSale), "Transfer token gagal");

        TokenSale memory sale = TokenSale({
            tokenAddress: _tokenAddress,
            owner: msg.sender,
            price: _price,
            amountForSale: _amountForSale,
            sold: 0,
            isActive: true,
            isPrivate: _isPrivate
        });

        tokenSales[_tokenAddress] = sale;
        listedTokens.push(_tokenAddress);

        emit TokenListed(_tokenAddress, msg.sender, _price, _amountForSale);
    }

    function buyToken(address _tokenAddress, uint256 _amount) external payable saleExists(_tokenAddress) {
        TokenSale storage sale = tokenSales[_tokenAddress];
        require(sale.isActive, "penjualan belum aktif");
        require(!sale.isPrivate, "ini adalah private sale");
        require(_amount > 0 && _amount <= (sale.amountForSale - sale.sold), "Jumlah salah");
        require(msg.value == (_amount * sale.price), "Incorrect ETH sent");

        sale.sold += _amount;

        IERC20 token = IERC20(_tokenAddress);
        require(token.transfer(msg.sender, _amount), "Gagal Transfer Token");

        emit TokenBought(msg.sender, _tokenAddress, _amount, msg.value);
    }

    function updateSale(address _tokenAddress, bool _isActive, uint256 _price)
        external
        saleExists(_tokenAddress)
    {
        TokenSale storage sale = tokenSales[_tokenAddress];
        require(msg.sender == admin || msg.sender == sale.owner, "Ga Boleh Gituuu");

        sale.isActive = _isActive;
        if (_price > 0) {
            sale.price = _price;
        }

        emit SaleUpdated(_tokenAddress, _isActive, _price);
    }

    function withdrawFunds() external onlyAdmin {
        payable(admin).transfer(address(this).balance);
    }

    function getAllListedTokens() external view returns (address[] memory) {
        return listedTokens;
    }
}
