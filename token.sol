// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.7.0;


import "./safemath.sol";
import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";

contract TokenMTT is ChainlinkClient {

    using SafeMath for uint256;
    
    address payable public owner;
    string public constant name = "MereheadTestToken";
    string public constant symbol = "MTT";
    uint public constant decimal = 5;
    uint public totalSupply;
    
    uint256 public price;
    address private oracle; // Network: Kovan
    bytes32 private jobId;
    uint256 private fee;
    
    mapping (address => uint256) balances;
    mapping (address => mapping(address => uint256)) allowed;
    
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 value);
    
    constructor() public {
        owner = msg.sender;
        totalSupply = 100000000000000;
        balances[owner] += totalSupply;
        
        setPublicChainlinkToken();
        oracle = 0x2f90A6D021db21e1B2A077c5a37B3C7E75D15b7e;
        jobId = "29fa9aa13bf1468788b7cc4a500a45b8";
        fee = 0.1 * 10 ** 18; // 0.1 LINK
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value) public onlyOwner returns (bool success) {
        require(balances[msg.sender] >= _value);
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(balances[_from] >= _value);
        require(allowed[_from][msg.sender] >= _value);
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }
    
    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
    
    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }
    
    function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
        totalSupply = totalSupply.add(_amount);
        balances[_to] = balances[_to].add(_amount);
        emit Mint(_to, _amount);
        emit Transfer(address(0), _to, _amount);
        return true;
    }
    
    function burn(uint256 _value) public onlyOwner returns (bool) {
        require(_value > 0);
        require(_value <= balances[msg.sender]);

        address burner = msg.sender;
        balances[burner] = balances[burner].sub(_value);
        totalSupply = totalSupply.sub(_value);
        emit Burn(burner, _value);
        return true;
    }
    
    receive() external payable {
        owner.transfer(msg.value);
    }
    
    
    // Chainlink API to ETHUSD price
    function requestPriceData() public returns (bytes32 requestId) {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        request.add("get", "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=ETH&tsyms=USD");
        request.add("path", "RAW.ETH.USD.PRICE");
        
        int priceWeiAmount = 10**18;
        request.addInt("price", priceWeiAmount);
        
        // Sends the request
        return sendChainlinkRequestTo(oracle, request, fee);
    }
    
    // Receive the response in the form of uint256
    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        price = _price;
    }
    
    /* Можно было реализовать получение ETHUSD через этот апи (было бы без траты газа),
       но я пока что не нашел ответ, как из int преобразовать в uint: 
    
        AggregatorV3Interface internal priceFeed;
        **
         * Network: Kovan
         * Aggregator: ETH/USD
         * Address: 0x9326BFA02ADD2366b30bacB125260Af641031331
         *
        constructor() public {
            priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
        }
        // Returns the latest price
        function getLatestPrice() public view returns (int) {
            (,int price,,,) = priceFeed.latestRoundData();
            return price;
        }

    */
    
    event Exchange(address indexed _buyer, uint _amountMTT, uint _cost, uint _balance);
    
    function exchange(uint _amountMTT) public payable returns (bool) {
        uint currencyETHUSD = price * 1 ether;                   // ~2000$ in wei
        uint currencyRate = 500000000000000000 / currencyETHUSD; // 1 MTT = 0.5$ in wei
        uint cost = _amountMTT * currencyRate;                   
    
        require(msg.value >= cost, "not enough ether");
        assert(transfer(msg.sender, _amountMTT));
        
        emit Exchange(msg.sender, _amountMTT, cost, balanceOf(msg.sender));
        return true;
    }
    
    /* 
       функция exchange не работает нужным образом, 
       как я понял, то когда эфир отправляется на конракт, 
       его можно получить функцией receive(), эфир на конракт приходил, 
       но всё равно функция не возвращала нужное количество токенов обратно покупателю
    */

}

