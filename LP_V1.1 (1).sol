// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
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
    event FundsWithdrawn(address indexed admin, uint256 amount);
    event TokenWithdrawn(address indexed owner, address indexed token, uint256 amount);
    event ProceedsWithdrawn(address indexed seller, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Hanya Admin Yang Boleh , Ente Siapa");
        _;
    }

    modifier saleExists(address token) {
        require(tokenSales[token].tokenAddress != address(0), "Ruko Masih Tutup");
        _;
    }

    modifier onlySaleOwner(address token) {
        require(tokenSales[token].owner == msg.sender, "Bukan Yang Punya Ruko");
        _;
    }

    constructor() {
        admin = msg.sender;
    }
    //fix code for @audit listToken does not check if the _tokenAddress is already exists in the tokenSales mapping

    function listToken(address _tokenAddress, uint256 _price, uint256 _amountForSale, bool _isPrivate) external {
        require(_tokenAddress != address(0), "Alamat token tidak valid");
        require(_price > 0, "Harga harus lebih besar dari 0");
        require(_amountForSale > 0 && _amountForSale <= 1_000_000 ether, "Jumlah token tidak valid"); // Contoh batas maksimum

        // Validasi apakah token sesuai standar ERC20
        require(_supportsERC20(_tokenAddress), "Token tidak sesuai ERC20");

        // Pastikan token belum terdaftar sebelumnya
        require(tokenSales[_tokenAddress].tokenAddress == address(0), "Token sudah terdaftar");

        IERC20 token = IERC20(_tokenAddress);

        // Fixing Tax Token
        uint256 initialBalance = token.balanceOf(address(this));
        token.transferFrom(msg.sender, address(this), _amountForSale);
        uint256 receivedAmount = token.balanceOf(address(this)) - initialBalance;

        require(receivedAmount > 0, "Transfer token gagal");
        require(receivedAmount == _amountForSale, "Token dengan mekanisme tax tidak didukung");

        // Validasi saldo dan izin
        require(token.balanceOf(msg.sender) >= _amountForSale, "Saldo token tidak cukup");
        require(token.allowance(msg.sender, address(this)) >= _amountForSale, "Izin transfer tidak cukup");

        // Transfer token ke kontrak
        require(token.transferFrom(msg.sender, address(this), _amountForSale), "Transfer token gagal");

        TokenSale memory sale = TokenSale({
            tokenAddress: _tokenAddress,
            owner: msg.sender,
            price: _price,
            amountForSale: receivedAmount,
            sold: 0,
            isActive: true,
            isPrivate: _isPrivate
        });

        tokenSales[_tokenAddress] = sale;
        listedTokens.push(_tokenAddress);

        emit TokenListed(_tokenAddress, msg.sender, _price, receivedAmount);
    }

    // Fungsi untuk validasi ERC20
    function _supportsERC20(address _tokenAddress) internal view returns (bool) {
        try IERC20(_tokenAddress).balanceOf(address(0)) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }
    //function listToken(address _tokenAddress, uint256 _price, uint256 _amountForSale, bool _isPrivate) external {
    //require(_price > 0, "Harga lebih besar dari 0");
    //require(_amountForSale > 0, "Jumlah harus lebih besar dari 0");

    //IERC20 token = IERC20(_tokenAddress);
    // require(token.transferFrom(msg.sender, address(this), _amountForSale), "Transfer token gagal");

    //TokenSale memory sale = TokenSale({
    //tokenAddress: _tokenAddress,
    // owner: msg.sender,
    // price: _price,
    // amountForSale: _amountForSale,
    //sold: 0,
    // isActive: true,
    // isPrivate: _isPrivate
    // });

    // tokenSales[_tokenAddress] = sale;
    //listedTokens.push(_tokenAddress);

    //emit TokenListed(_tokenAddress, msg.sender, _price, _amountForSale);
    // }

    //function buyToken(address _tokenAddress, uint256 _amount) external payable saleExists(_tokenAddress) {
    //  TokenSale storage sale = tokenSales[_tokenAddress];
    //  require(sale.isActive, "penjualan belum aktif");
    //  require(!sale.isPrivate, "ini adalah private sale");
    //  require(_amount > 0 && _amount <= (sale.amountForSale - sale.sold), "Jumlah salah");
    // require(msg.value == (_amount * sale.price), "Jumlah ETH Salah Bor");

    //  sale.sold += _amount;

    //IERC20 token = IERC20(_tokenAddress);
    //require(token.transfer(msg.sender, _amount), "Gagal Transfer Token");

    //emit TokenBought(msg.sender, _tokenAddress, _amount, msg.value);
    // }

    mapping(address => uint256) public proceeds;

    function buyToken(address _tokenAddress, uint256 _amount) external payable saleExists(_tokenAddress) {
        // Gunakan memory untuk membaca data dari storage
        TokenSale memory sale = tokenSales[_tokenAddress];

        // Validasi kondisi penjualan
        require(sale.isActive, "Penjualan belum aktif");
        require(!sale.isPrivate, "Ini adalah private sale");
        require(_amount > 0 && _amount <= sale.amountForSale, "Jumlah salah");
        require(msg.value == (_amount * sale.price), "ETH yang dikirim tidak sesuai");

        sale.sold += _amount;
        // Hasil Penjualan Token
        proceeds[sale.owner] += msg.value;

        // fix @audit info if the token is sold, mark the token as inactive
        sale.amountForSale -= _amount; // Kurangi langsung stok token
        if (sale.amountForSale == 0) {
            sale.isActive = false; // Nonaktifkan penjualan jika token habis
        }

        // Transfer token setelah memperbarui state
        IERC20 token = IERC20(_tokenAddress);
        require(token.transfer(msg.sender, _amount), "Gagal transfer token");

        emit TokenBought(msg.sender, _tokenAddress, _amount, msg.value);
    }

    function updateSale(address _tokenAddress, bool _isActive, uint256 _price) external saleExists(_tokenAddress) {
        // fix for @audit gas use memory instead of storage
        TokenSale memory sale = tokenSales[_tokenAddress];
        require(msg.sender == admin || msg.sender == sale.owner, "kamu Ga Boleh Gituuu");

        sale.isActive = _isActive;
        if (_price > 0) {
            sale.price = _price;
        }

        emit SaleUpdated(_tokenAddress, _isActive, _price);
    }
    // fixing @audit sale.owner does not have any mean to withdraw funds from their sale

    function withdrawFunds(uint256 _amount) external onlyAdmin {
        uint256 contractBalance = address(this).balance;
        require(_amount > 0, "Jumlah harus lebih besar dari 0");
        require(_amount <= contractBalance, "Jumlah melebihi saldo kontrak");
        // fixing @audit Use Call Instead Of Transfer
        (bool success,) = admin.call{value: _amount}("");
        require(success, "Transfer gagal");

        emit FundsWithdrawn(admin, _amount);
    }

    // Fix dan Penambahan Fungsi Withdraw Untuk User yang melakukan Listing
    function withdrawToken(address _tokenAddress) external saleExists(_tokenAddress) onlySaleOwner(_tokenAddress) {
        TokenSale storage sale = tokenSales[_tokenAddress];
        require(!sale.isActive, "Penjualan masih aktif, tidak bisa menarik token");

        uint256 unsoldTokens = sale.amountForSale - sale.sold;
        require(unsoldTokens > 0, "Tidak ada token yang tersisa untuk ditarik");

        sale.amountForSale = 0; // Update jumlah token yang terdaftar menjadi nol

        IERC20 token = IERC20(_tokenAddress);
        require(token.transfer(msg.sender, unsoldTokens), "Gagal menarik token");

        emit TokenWithdrawn(msg.sender, _tokenAddress, unsoldTokens);
    }

    // Fungsi Witdraw Hasil Penjualan Token User
    function withdrawProceeds() external {
        uint256 amount = proceeds[msg.sender];
        require(amount > 0, "Tidak ada hasil untuk ditarik");

        proceeds[msg.sender] = 0; // Pastikan untuk menghindari reentrancy
        payable(msg.sender).transfer(amount);

        emit ProceedsWithdrawn(msg.sender, amount);
    }

    //function withdrawFunds() external onlyAdmin {
    //  payable(admin).transfer(address(this).balance);
    //}

    function getAllListedTokens() external view returns (address[] memory) {
        return listedTokens;
    }
}
