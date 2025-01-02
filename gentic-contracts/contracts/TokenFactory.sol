// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./Token.sol";
import "hardhat/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

contract TokenFactory is Ownable {
    struct AgentToken {
        string name;
        string symbol;
        string description;
        string tokenImageUrl;
        uint256 generation;
        uint256 familyCode;
        uint256 serialNumber;
        uint256 mcap;
        uint256 fundingRaised;
        uint256 lastActivityTime;
        address tokenAddress;
        address creatorAddress;
        bool inCooldown;
    }

    address[] public agentTokenAddresses;
    mapping(address => AgentToken) public addressToAgentTokenMapping;
    mapping(address => uint256) public tokenFitness;

    event TokensSold(address indexed seller, address indexed tokenAddress, uint256 amount, uint256 ethReceived);
    event BreedingProposed(address indexed proposer, address indexed parent1, address indexed parent2);
    event BreedingSuccessful(address indexed child, address indexed parent1, address indexed parent2);

    // Constants
    uint256 constant AGENT_CREATION_COST = 1000 ether; // 1000 ETH
    uint256 constant BREEDING_PROPOSAL_COST = 100 ether; // 100 ETH
    uint256 constant MIN_MCAP_AWAKE = 100000 ether; // $100k
    uint256 constant COOLDOWN_PERIOD = 7 days;
    uint256 constant DECIMALS = 10 ** 18;
    uint256 constant INITIAL_SUPPLY = 1000000000 * DECIMALS; // 1B tokens
    uint256 constant INITIAL_MCAP = 10000; // $10k

    // Bonding curve parameters
    uint256 public constant INITIAL_PRICE = 5000000000000000; // Initial price in wei
    uint256 public constant K = 8 * 10 ** 15; // Growth rate

    constructor() Ownable(msg.sender) {}

    function createAgentToken(
        string memory name,
        string memory symbol,
        string memory imageUrl,
        string memory description,
        uint256 generation,
        uint256 familyCode,
        uint256 serialNumber
    ) public payable returns (address) {
        require(msg.value >= AGENT_CREATION_COST, "Insufficient creation cost");

        Token token = new Token(name, symbol, INITIAL_SUPPLY);
        address tokenAddress = address(token);

        AgentToken memory newAgent = AgentToken({
            name: name,
            symbol: symbol,
            description: description,
            tokenImageUrl: imageUrl,
            generation: generation,
            familyCode: familyCode,
            serialNumber: serialNumber,
            mcap: INITIAL_MCAP,
            fundingRaised: 0,
            lastActivityTime: block.timestamp,
            tokenAddress: tokenAddress,
            creatorAddress: msg.sender,
            inCooldown: false
        });

        agentTokenAddresses.push(tokenAddress);
        addressToAgentTokenMapping[tokenAddress] = newAgent;

        // Distribute initial tokens according to schema
        _distributeInitialTokens(token);

        return tokenAddress;
    }

    function _distributeInitialTokens(Token token) internal {
        // 0.01% to operational wallet
        token.transfer(owner(), INITIAL_SUPPLY * 1 / 10000);
        
        // 5% to compute reserve
        token.transfer(address(this), INITIAL_SUPPLY * 5 / 100);
        
        // 10% to MPC operations
        token.transfer(address(this), INITIAL_SUPPLY * 10 / 100);
        
        // 10% to breeding reserve
        token.transfer(address(this), INITIAL_SUPPLY * 10 / 100);
        
        // 20% to liquidity pool
        token.transfer(address(this), INITIAL_SUPPLY * 20 / 100);
        
        // 55% to bonding curve
        token.transfer(address(this), INITIAL_SUPPLY * 55 / 100);
    }

    function calculateFitness(address tokenAddress) public view returns (uint256) {
        AgentToken storage agent = addressToAgentTokenMapping[tokenAddress];
        require(agent.tokenAddress != address(0), "Token not found");

        // Fitness = w₁Mcap + w₂Volume + Age
        uint256 mcapWeight = 40;
        uint256 volumeWeight = 30;
        uint256 ageWeight = 30;

        uint256 mcapScore = (agent.mcap * mcapWeight) / 100;
        uint256 volumeScore = (agent.fundingRaised * volumeWeight) / 100;
        uint256 ageScore = ((block.timestamp - agent.lastActivityTime) * ageWeight) / 100;

        return mcapScore + volumeScore + ageScore;
    }

    function proposeBreeding(address parent1, address parent2) public payable {
        require(msg.value >= BREEDING_PROPOSAL_COST, "Insufficient breeding cost");
        require(_validateBreedingPair(parent1, parent2), "Invalid breeding pair");

        emit BreedingProposed(msg.sender, parent1, parent2);
    }

    function _validateBreedingPair(address parent1, address parent2) internal view returns (bool) {
        AgentToken storage agent1 = addressToAgentTokenMapping[parent1];
        AgentToken storage agent2 = addressToAgentTokenMapping[parent2];

        require(!agent1.inCooldown && !agent2.inCooldown, "Parents in cooldown");
        require(agent1.familyCode != agent2.familyCode, "Same family breeding not allowed");
        require(agent1.generation == agent2.generation, "Must be same generation");
        require(agent1.mcap >= MIN_MCAP_AWAKE && agent2.mcap >= MIN_MCAP_AWAKE, "Insufficient mcap");

        return true;
    }

    // Function to calculate the cost in wei for purchasing `tokensToBuy` starting from `currentSupply`
    function calculateCost(uint256 currentSupply, uint256 tokensToBuy) public pure returns (uint256) {
        // Calculate the exponent parts scaled to avoid precision loss
        uint256 exponent1 = (K * (currentSupply + tokensToBuy)) / 10 ** 18;
        uint256 exponent2 = (K * currentSupply) / 10 ** 18;

        // Calculate e^(kx) using the exp function
        uint256 exp1 = exp(exponent1);
        uint256 exp2 = exp(exponent2);

        // Cost formula: (P0 / k) * (e^(k * (currentSupply + tokensToBuy)) - e^(k * currentSupply))
        // We use (P0 * 10^18) / k to keep the division safe from zero
        uint256 cost = (INITIAL_PRICE * 10 ** 18 * (exp1 - exp2)) / K; // Adjust for k scaling without dividing by zero
        return cost;
    }

    function calculateBuyTokenCost(address tokenAddress, uint256 tokenQty) public view returns (uint256) {
        require(addressToAgentTokenMapping[tokenAddress].tokenAddress != address(0), "Token not listed");
        
        Token token = Token(tokenAddress);
        uint256 currentSupply = token.totalSupply();
        uint256 currentSupplyScaled = currentSupply / DECIMALS;
        
        // Calculate the exponent parts scaled to avoid precision loss
        uint256 exponent1 = (K * (currentSupplyScaled + tokenQty)) / 10 ** 18;
        uint256 exponent2 = (K * currentSupplyScaled) / 10 ** 18;

        // Calculate e^(kx) using the exp function
        uint256 exp1 = exp(exponent1);
        uint256 exp2 = exp(exponent2);

        // Cost formula in ethers: (P0 / k) * (e^(k * (currentSupply + tokensToBuy)) - e^(k * currentSupply))
        uint256 costInEthers = (INITIAL_PRICE * (exp1 - exp2)) / K;
        
        // Add buy fee (5%)
        uint256 buyFee = (costInEthers * 5) / 100;
        uint256 totalCostInEthers = costInEthers + buyFee;
        
        return totalCostInEthers;
    }

    // Improved helper function to calculate e^x for larger x using a Taylor series approximation
    function exp(uint256 x) internal pure returns (uint256) {
        uint256 sum = 10 ** 18; // Start with 1 * 10^18 for precision
        uint256 term = 10 ** 18; // Initial term = 1 * 10^18
        uint256 xPower = x; // Initial power of x

        for (uint256 i = 1; i <= 20; i++) {
            // Increase iterations for better accuracy
            term = (term * xPower) / (i * 10 ** 18); // x^i / i!
            sum += term;

            // Prevent overflow and unnecessary calculations
            if (term < 1) break;
        }

        return sum;
    }

    function createMemeToken(
        string memory name,
        string memory symbol,
        string memory imageUrl,
        string memory description
    ) public payable returns (address) {
        // Define the required amount of PToken
        uint256 requiredAmount = MEMETOKEN_CREATION_PLATFORM_FEE * DECIMALS; // Assuming PToken has 18 decimals

        // Check if the user has approved enough tokens for the contract
        IERC20 pToken = IERC20(pTokenAddress);
        require(pToken.allowance(msg.sender, address(this)) >= requiredAmount, "Insufficient allowance for PToken");

        // Transfer the required amount of PToken from the sender to the contract
        require(pToken.transferFrom(msg.sender, address(this), requiredAmount), "PToken transfer failed");

        Token ct = new Token(name, symbol, INIT_SUPPLY);
        address memeTokenAddress = address(ct);
        memeToken memory newlyCreatedToken =
            memeToken(name, symbol, description, imageUrl, 0, memeTokenAddress, msg.sender);
        memeTokenAddresses.push(memeTokenAddress);
        addressToMemeTokenMapping[memeTokenAddress] = newlyCreatedToken;
        return memeTokenAddress;
    }

    function getAllMemeTokens() public view returns (memeToken[] memory) {
        memeToken[] memory allTokens = new memeToken[](memeTokenAddresses.length);
        for (uint256 i = 0; i < memeTokenAddresses.length; i++) {
            allTokens[i] = addressToMemeTokenMapping[memeTokenAddresses[i]];
        }
        return allTokens;
    }

    function sellMemeToken(address memeTokenAddress, uint256 tokenQty) public returns (uint256) {
        // Check if memecoin is listed
        require(addressToMemeTokenMapping[memeTokenAddress].tokenAddress != address(0), "Token is not listed");

        memeToken storage listedToken = addressToMemeTokenMapping[memeTokenAddress];
        Token memeTokenCt = Token(memeTokenAddress);

        // Scale the token quantity
        uint256 tokenQty_scaled = tokenQty * DECIMALS;

        // Check if user has enough tokens to sell
        require(memeTokenCt.balanceOf(msg.sender) >= tokenQty_scaled, "Insufficient token balance");

        // Calculate the amount of PToken to return using the bonding curve
        uint256 currentSupply = memeTokenCt.totalSupply();
        uint256 currentSupplyScaled = (currentSupply - INIT_SUPPLY) / DECIMALS;
        uint256 pTokenToReturn = calculateCost(currentSupplyScaled - tokenQty, tokenQty);

        // Apply a sell fee (5%)
        uint256 sellFee = (pTokenToReturn * 5) / 100;
        uint256 pTokenAfterFee = pTokenToReturn - sellFee;

        // Check if contract has enough PToken balance
        IERC20 pToken = IERC20(pTokenAddress);
        require(pToken.balanceOf(address(this)) >= pTokenAfterFee, "Insufficient PToken in contract");

        // Transfer tokens from seller to contract and then burn them
        require(memeTokenCt.transferFrom(msg.sender, address(this), tokenQty_scaled), "Token transfer failed");
        memeTokenCt.burn(tokenQty_scaled, address(this));

        // Transfer PToken to seller
        require(pToken.transfer(msg.sender, pTokenAfterFee), "PToken transfer failed");

        // Update funding raised (decrease it by the amount returned)
        if (listedToken.fundingRaised > pTokenToReturn) {
            listedToken.fundingRaised -= pTokenToReturn;
        } else {
            listedToken.fundingRaised = 0;
        }

        // Emit the sell event
        emit TokensSold(msg.sender, memeTokenAddress, tokenQty_scaled, pTokenAfterFee);

        return pTokenAfterFee;
    }

    function calculateSellReturn(address memeTokenAddress, uint256 tokenQty) public view returns (uint256) {
        Token memeTokenCt = Token(memeTokenAddress);
        uint256 currentSupply = memeTokenCt.totalSupply();
        uint256 currentSupplyScaled = (currentSupply - INIT_SUPPLY) / DECIMALS;
        uint256 pTokenToReturn = calculateCost(currentSupplyScaled - tokenQty, tokenQty);

        // Apply sell fee
        uint256 sellFee = (pTokenToReturn * 5) / 100;
        return pTokenToReturn - sellFee;
    }

    function buyMemeToken(address memeTokenAddress, uint256 tokenQty) public returns (uint256) {
        // Check if memecoin is listed
        require(addressToMemeTokenMapping[memeTokenAddress].tokenAddress != address(0), "Token is not listed");

        memeToken storage listedToken = addressToMemeTokenMapping[memeTokenAddress];
        Token memeTokenCt = Token(memeTokenAddress);

        // Check to ensure funding goal is not met
        require(listedToken.fundingRaised <= MEMECOIN_FUNDING_GOAL, "Funding has already been raised");

        // Check to ensure there is enough supply to facilitate the purchase
        uint256 currentSupply = memeTokenCt.totalSupply();
        uint256 available_qty = MAX_SUPPLY - currentSupply;
        uint256 scaled_available_qty = available_qty / DECIMALS;
        uint256 tokenQty_scaled = tokenQty * DECIMALS;

        require(tokenQty <= scaled_available_qty, "Not enough available supply");

        // Calculate the cost for purchasing tokenQty tokens using the bonding curve formula
        uint256 currentSupplyScaled = (currentSupply - INIT_SUPPLY) / DECIMALS;
        uint256 requiredPToken = calculateCost(currentSupplyScaled, tokenQty);

        // Check if user has approved and has enough PToken balance
        IERC20 pToken = IERC20(pTokenAddress); // Ensure `pTokenAddress` is initialized elsewhere in the contract
        require(pToken.allowance(msg.sender, address(this)) >= requiredPToken, "Insufficient PToken allowance");
        require(pToken.balanceOf(msg.sender) >= requiredPToken, "Insufficient PToken balance");

        // console.log(requiredPToken);
        // Transfer PToken from the user to the contract
        require(pToken.transferFrom(msg.sender, address(this), requiredPToken), "PToken transfer failed");

        // Increment the funding raised
        listedToken.fundingRaised += requiredPToken;

        if (listedToken.fundingRaised >= MEMECOIN_FUNDING_GOAL) {
            // Create liquidity pool
            _createLiquidityPool(memeTokenAddress);

            // Provide liquidity
            uint256 pTokenAmount = 60 * listedToken.fundingRaised / 100;
            _provideLiquidity(memeTokenAddress, INIT_SUPPLY, pTokenAmount);

            // Burn LP tokens
            // _burnLpTokens(pool, liquidity);
        }

        // Mint the tokens to the buyer
        memeTokenCt.mint(tokenQty_scaled, msg.sender);

        return 1;
    }

    function _createLiquidityPool(address memeTokenAddress) internal returns (address) {
        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_FACTORY_ADDRESS);
        address pair = factory.createPair(memeTokenAddress, pTokenAddress);
        return pair;
    }

    function _provideLiquidity(address memeTokenAddress, uint256 atokenAmount, uint256 pTokenAmount)
        internal
        returns (uint256)
    {
        Token memeTokenCt = Token(memeTokenAddress);
        memeTokenCt.mint(atokenAmount, address(this));
        memeTokenCt.approve(UNISWAP_V2_ROUTER_ADDRESS, atokenAmount);
        memeTokenCt.approve(UNISWAP_V2_ROUTER_ADDRESS, pTokenAmount);

        IUniswapV2Router router = IUniswapV2Router(UNISWAP_V2_ROUTER_ADDRESS);
        (,, uint256 liquidity) = router.addLiquidity(
            memeTokenAddress,
            pTokenAddress,
            atokenAmount,
            pTokenAmount,
            0, // amountAMin
            0, // amountBMin
            address(this), // to
            block.timestamp // deadline
        );
        return liquidity;
    }

    function _burnLpTokens(address pool, uint256 liquidity) internal returns (uint256) {
        IUniswapV2Pair uniswapv2pairct = IUniswapV2Pair(pool);
        uniswapv2pairct.transfer(address(0), liquidity);
        console.log("Uni v2 tokens burnt");
        return 1;
    }

    function withdrawPTOKEN() public onlyOwner {
        IERC20 pToken = IERC20(pTokenAddress);
        uint256 balance = pToken.balanceOf(address(this));
        require(balance > 0, "No PTOKEN to withdraw");

        bool success = pToken.transfer(msg.sender, balance);
        require(success, "PTOKEN withdrawal failed");
    }

    function completeBreeding(
        address parent1,
        address parent2,
        string memory name,
        string memory symbol,
        string memory imageUrl,
        string memory description
    ) external returns (address) {
        require(msg.sender == owner(), "Only owner can complete breeding");
        require(_validateBreedingPair(parent1, parent2), "Invalid breeding pair");

        AgentToken storage agent1 = addressToAgentTokenMapping[parent1];
        AgentToken storage agent2 = addressToAgentTokenMapping[parent2];

        // Create child token
        Token token = new Token(
            name,
            symbol,
            INITIAL_SUPPLY,
            agent1.generation + 1,
            _generateFamilyCode(agent1.familyCode, agent2.familyCode),
            agentTokenAddresses.length
        );

        address childAddress = address(token);

        // Create child agent record
        AgentToken memory childAgent = AgentToken({
            name: name,
            symbol: symbol,
            description: description,
            tokenImageUrl: imageUrl,
            generation: agent1.generation + 1,
            familyCode: _generateFamilyCode(agent1.familyCode, agent2.familyCode),
            serialNumber: agentTokenAddresses.length,
            mcap: INITIAL_MCAP,
            fundingRaised: 0,
            lastActivityTime: block.timestamp,
            tokenAddress: childAddress,
            creatorAddress: msg.sender,
            inCooldown: false
        });

        agentTokenAddresses.push(childAddress);
        addressToAgentTokenMapping[childAddress] = childAgent;

        // Distribute initial tokens with parent inheritance
        _distributeBreedingTokens(token, parent1, parent2);

        // Put parents in cooldown
        Token(parent1).startCooldown();
        Token(parent2).startCooldown();

        emit BreedingSuccessful(childAddress, parent1, parent2);
        return childAddress;
    }

    function _distributeBreedingTokens(Token token, address parent1, address parent2) internal {
        // 0.01% to operational wallet
        token.transfer(owner(), INITIAL_SUPPLY * 1 / 10000);
        
        // 10% to each parent (20% total)
        token.transfer(parent1, INITIAL_SUPPLY * 10 / 100);
        token.transfer(parent2, INITIAL_SUPPLY * 10 / 100);
        
        // 5% to compute reserve
        token.transfer(address(this), INITIAL_SUPPLY * 5 / 100);
        
        // 10% to MPC operations
        token.transfer(address(this), INITIAL_SUPPLY * 10 / 100);
        
        // 10% to breeding reserve
        token.transfer(address(this), INITIAL_SUPPLY * 10 / 100);
        
        // 20% to liquidity pool
        token.transfer(address(this), INITIAL_SUPPLY * 20 / 100);
        
        // 25% to bonding curve (reduced from 55% due to parent inheritance)
        token.transfer(address(this), INITIAL_SUPPLY * 25 / 100);
    }

    function _generateFamilyCode(uint256 family1, uint256 family2) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(family1, family2, block.timestamp))) % 1000000;
    }
}
