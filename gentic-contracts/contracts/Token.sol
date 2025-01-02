// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    uint256 public generation;
    uint256 public familyCode;
    uint256 public serialNumber;
    uint256 public lastActivityTime;
    bool public inCooldown;
    
    uint256 public constant COOLDOWN_PERIOD = 7 days;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 _generation,
        uint256 _familyCode,
        uint256 _serialNumber
    ) ERC20(name, symbol) Ownable(msg.sender) {
        generation = _generation;
        familyCode = _familyCode;
        serialNumber = _serialNumber;
        lastActivityTime = block.timestamp;
        inCooldown = false;
        _mint(msg.sender, initialSupply);
    }

    function mint(uint256 amount, address to) public onlyOwner {
        _mint(to, amount);
        lastActivityTime = block.timestamp;
    }

    function burn(uint256 amount, address from) public {
        _burn(from, amount);
        lastActivityTime = block.timestamp;
    }

    function startCooldown() external onlyOwner {
        require(!inCooldown, "Already in cooldown");
        inCooldown = true;
        lastActivityTime = block.timestamp;
    }

    function endCooldown() external onlyOwner {
        require(inCooldown, "Not in cooldown");
        require(block.timestamp >= lastActivityTime + COOLDOWN_PERIOD, "Cooldown period not over");
        inCooldown = false;
        lastActivityTime = block.timestamp;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(!inCooldown, "Token is in cooldown");
        lastActivityTime = block.timestamp;
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!inCooldown, "Token is in cooldown");
        lastActivityTime = block.timestamp;
        return super.transferFrom(from, to, amount);
    }
}