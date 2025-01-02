// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AgentToken is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e18; // 1B tokens
    uint256 public constant INITIAL_MCAP = 10_000; // $10k

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(address(this), INITIAL_SUPPLY);
    }

    function distributeInitialTokens(
        address operationalWallet,
        address[] memory guardianNodes,
        address computeReserve,
        address mpcOperations,
        address breedingReserve,
        address liquidityPool,
        address bondingCurve
    ) external onlyOwner {
        require(guardianNodes.length == 10, "Must be 10 guardian nodes");

        // 0.01% to operational wallet
        _transfer(address(this), operationalWallet, INITIAL_SUPPLY * 1 / 10000);
        
        // 0.1% to guardian nodes (0.01% each)
        for(uint i = 0; i < guardianNodes.length; i++) {
            _transfer(address(this), guardianNodes[i], INITIAL_SUPPLY * 1 / 10000);
        }

        // 5% to compute reserve
        _transfer(address(this), computeReserve, INITIAL_SUPPLY * 5 / 100);
        
        // 10% to MPC operations
        _transfer(address(this), mpcOperations, INITIAL_SUPPLY * 10 / 100);
        
        // 10% to breeding reserve
        _transfer(address(this), breedingReserve, INITIAL_SUPPLY * 10 / 100);
        
        // 20% to liquidity pool
        _transfer(address(this), liquidityPool, INITIAL_SUPPLY * 20 / 100);
        
        // 55% to bonding curve
        _transfer(address(this), bondingCurve, INITIAL_SUPPLY * 55 / 100);
    }
}
