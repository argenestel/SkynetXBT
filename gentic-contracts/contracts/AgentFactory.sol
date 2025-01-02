// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AgentToken.sol";
import "./GeneticAgent.sol";
import "./TokenFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AgentFactory is Ownable {
    GeneticAgent public geneticAgent;
    TokenFactory public tokenFactory;

    event AgentDeployed(address agentToken, address geneticAgent);

    constructor(address _geneticAgent, address _tokenFactory) Ownable(msg.sender) {
        geneticAgent = GeneticAgent(_geneticAgent);
        tokenFactory = TokenFactory(_tokenFactory);
    }

    function deployNewAgent(
        string memory name,
        string memory symbol,
        string memory id,
        string memory imageUrl,
        string memory description,
        uint256 generation,
        uint256 familyCode,
        uint256 serialNum,
        bytes32[] memory initialTraits,
        uint256[] memory traitValues
    ) external payable returns (address, address) {
        // Create token through TokenFactory
        address tokenAddress = tokenFactory.createAgentToken(
            name,
            symbol,
            imageUrl,
            description,
            generation,
            familyCode,
            serialNum
        );
        
        // Create genetic agent
        geneticAgent.createAgent{value: msg.value}(
            id,
            generation,
            familyCode,
            initialTraits,
            traitValues
        );
        
        emit AgentDeployed(tokenAddress, address(geneticAgent));
        return (tokenAddress, address(geneticAgent));
    }

    // Allow contract to receive ETH
    receive() external payable {}
} 