// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GeneticAgent.sol";
import "./GuardianNode.sol";
import "./TokenFactory.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Breeding is ReentrancyGuard {
    struct BreedingProposal {
        address proposer;
        string parent1Id;
        string parent2Id;
        uint256 timestamp;
        uint256 approvals;
        bool executed;
        mapping(address => bool) hasVoted;
        string name;
        string symbol;
        string imageUrl;
        string description;
    }

    struct BreedingRules {
        uint256 minParentFitness;
        uint256 maxGenerationGap;
        uint256 minMcap;
        uint256 cooldownPeriod;
        uint256 requiredApprovals;
    }

    GeneticAgent public geneticAgent;
    GuardianNode public guardianNode;
    TokenFactory public tokenFactory;
    BreedingRules public rules;
    
    mapping(uint256 => BreedingProposal) public proposals;
    uint256 public proposalCounter;
    
    event BreedingProposed(uint256 indexed proposalId, string parent1Id, string parent2Id);
    event GuardianVoted(uint256 indexed proposalId, address indexed guardian);
    event BreedingSuccessful(string parent1Id, string parent2Id, string childId);
    event TraitInherited(string childId, bytes32 traitKey, uint256 value);

    constructor(
        address _geneticAgent,
        address _guardianNode,
        address _tokenFactory
    ) {
        geneticAgent = GeneticAgent(_geneticAgent);
        guardianNode = GuardianNode(_guardianNode);
        tokenFactory = TokenFactory(_tokenFactory);
        
        rules = BreedingRules({
            minParentFitness: 1000,
            maxGenerationGap: 2,
            minMcap: 50000,
            cooldownPeriod: 7 days,
            requiredApprovals: 6 // 60% of guardians must approve
        });
    }

    function submitBreedingProposal(
        string memory parent1Id,
        string memory parent2Id,
        string memory name,
        string memory symbol,
        string memory imageUrl,
        string memory description
    ) external payable nonReentrant {
        require(msg.value >= geneticAgent.CREATION_COST(), "Insufficient breeding cost");
        require(_validateBreedingPair(parent1Id, parent2Id), "Invalid breeding pair");

        uint256 proposalId = proposalCounter++;
        BreedingProposal storage proposal = proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.parent1Id = parent1Id;
        proposal.parent2Id = parent2Id;
        proposal.timestamp = block.timestamp;
        proposal.name = name;
        proposal.symbol = symbol;
        proposal.imageUrl = imageUrl;
        proposal.description = description;

        emit BreedingProposed(proposalId, parent1Id, parent2Id);
    }

    function voteOnProposal(uint256 proposalId) external {
        require(guardianNode.hasRole(guardianNode.GUARDIAN_ROLE(), msg.sender), "Not a guardian");
        
        BreedingProposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(block.timestamp <= proposal.timestamp + 1 days, "Voting period ended");

        proposal.hasVoted[msg.sender] = true;
        proposal.approvals++;

        emit GuardianVoted(proposalId, msg.sender);

        // If enough approvals, execute breeding
        if (proposal.approvals >= rules.requiredApprovals) {
            _executeBreeding(proposalId);
        }
    }

    function _executeBreeding(uint256 proposalId) internal {
        BreedingProposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Already executed");
        
        // Get parent token addresses
        (address parent1Token,) = geneticAgent.getAgentDetails(proposal.parent1Id);
        (address parent2Token,) = geneticAgent.getAgentDetails(proposal.parent2Id);

        // Complete breeding through TokenFactory
        address childToken = tokenFactory.completeBreeding(
            parent1Token,
            parent2Token,
            proposal.name,
            proposal.symbol,
            proposal.imageUrl,
            proposal.description
        );

        // Inherit traits
        _inheritTraits(proposal.parent1Id, proposal.parent2Id, childToken);

        proposal.executed = true;
        emit BreedingSuccessful(proposal.parent1Id, proposal.parent2Id, proposal.name);
    }

    function _validateBreedingPair(
        string memory parent1Id,
        string memory parent2Id
    ) internal view returns (bool) {
        (uint256 gen1, uint256 fam1, uint256 fit1) = geneticAgent.getAgentDetails(parent1Id);
        (uint256 gen2, uint256 fam2, uint256 fit2) = geneticAgent.getAgentDetails(parent2Id);

        require(fam1 != fam2, "Same family breeding not allowed");
        require(
            abs(int256(gen1) - int256(gen2)) <= rules.maxGenerationGap,
            "Generation gap too large"
        );
        require(
            fit1 >= rules.minParentFitness && fit2 >= rules.minParentFitness,
            "Insufficient fitness"
        );

        return true;
    }

    function _inheritTraits(
        string memory parent1Id,
        string memory parent2Id,
        address childToken
    ) internal {
        bytes32[] memory traitKeys = geneticAgent.getTraitKeys(parent1Id);
        
        for (uint i = 0; i < traitKeys.length; i++) {
            (uint256 value1, uint256 dom1) = geneticAgent.getTraitDetails(parent1Id, traitKeys[i]);
            (uint256 value2, uint256 dom2) = geneticAgent.getTraitDetails(parent2Id, traitKeys[i]);
            
            uint256 inheritedValue;
            if (dom1 > dom2) {
                inheritedValue = value1;
            } else if (dom2 > dom1) {
                inheritedValue = value2;
            } else {
                // Equal dominance - take average with mutation chance
                inheritedValue = (value1 + value2) / 2;
                if (_shouldMutate()) {
                    inheritedValue = _applyMutation(inheritedValue);
                }
            }
            
            // Set trait in child token
            geneticAgent.setTrait(childToken, traitKeys[i], inheritedValue);
            emit TraitInherited(Token(childToken).name(), traitKeys[i], inheritedValue);
        }
    }

    function _shouldMutate() internal view returns (bool) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 100 < 5; // 5% mutation chance
    }

    function _applyMutation(uint256 value) internal view returns (uint256) {
        uint256 mutationFactor = uint256(keccak256(abi.encodePacked(block.timestamp))) % 30 + 85; // ±15% mutation
        return (value * mutationFactor) / 100;
    }

    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
} 