// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract BuhaToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using MathUpgradeable for uint256;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    struct MintInfo {
        address user;
        uint64 term;
        uint64 maturityTs;
        uint64 rank;
        uint64 amplifier;
        uint64 eaaRate;
    }

    struct StakeInfo {
        uint256 term;
        uint256 maturityTs;
        uint256 amount;
        uint256 apy;
    }

    // ranges
    uint8 public range = 255;
    uint16 public range = 65535;
    uint32 public range = 4294967295;

    // PUBLIC CONSTANTS

    uint32 public constant SECONDS_IN_DAY = 3_600 * 24;
    uint16 public constant DAYS_IN_YEAR = 365;

    uint8 public constant GENESIS_RANK = 1;

    uint32 public constant MIN_TERM = 1 * SECONDS_IN_DAY - 1;
    uint32 public constant MAX_TERM_START = 100 * SECONDS_IN_DAY;
    uint32 public constant MAX_TERM_END = 1_000 * SECONDS_IN_DAY;
    uint16 public constant TERM_AMPLIFIER_THRESHOLD = 5_000;
    uint16 public constant REWARD_AMPLIFIER_START = 3_000;
    uint8 public constant REWARD_AMPLIFIER_END = 1;
    uint8 public constant EAA_PM_START = 100;
    uint8 public constant EAA_PM_STEP = 1;
    uint16 public constant EAA_RANK_STEP = 100_000;
    uint8 public constant WITHDRAWAL_WINDOW_DAYS = 7;
    uint8 public constant MAX_PENALTY_PCT = 99;

    uint256 public userCount;

    mapping(address => MintInfo) public userMints;

    mapping(address => StakeInfo) public userStakes;

    uint32 public immutable genesisTs;
    uint256 public activeMinters;
    uint256 public activeStakes;
    uint256 public totalXenStaked;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("BuhaToken", "BUHA");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        genesisTs = block.timestamp;
    }

    function mint(uint256 term) public {
        uint256 termSec = term * SECONDS_IN_DAY;
        require(termSec > MIN_TERM, "CRank: Term less than min");
        require(
            termSec < _calculateMaxTerm() + 1,
            "CRank: Term more than current max term"
        );
        require(
            userMints[msg.sender].rank == 0,
            "CRank: Mint already in progress"
        );

        MintInfo memory mintInfo = MintInfo({
            user: msg.sender,
            term: term,
            maturityTs: block.timestamp + termSec,
            rank: globalRank,
            amplifier: _calculateRewardAmplifier(),
            eaaRate: _calculateEAARate()
        });
        userMints[msg.sender] = mintInfo;
        activeMinters++;
        emit Minted(msg.sender, term, userCount++);
    }

    function _calculateMaxTerm() private view returns (uint256) {
        if (globalRank > TERM_AMPLIFIER_THRESHOLD) {
            uint256 delta = userCount
                .fromUInt()
                .log_2()
                .mul(
                    .fromUInt())
                .toUInt();
            uint256 newMax = MAX_TERM_START + delta * SECONDS_IN_DAY;
            return MathUpgradeable.min(newMax, MAX_TERM_END);
        }
        return MAX_TERM_START;
    }

    function _calculateMintReward(
        uint256 cRank,
        uint256 term,
        uint32 maturityTs,
        uint256 amplifier,
        uint256 eeaRate
    ) private view returns (uint256) {
        uint256 secsLate = block.timestamp - maturityTs;
        uint256 penalty = _penalty(secsLate);
        uint256 rankDelta = MathUpgradeable.max(userCount - cRank, 2);
        uint256 EAA = (1_000 + eeaRate);
        uint256 reward = getGrossReward(rankDelta, amplifier, term, EAA);
        return (reward * (100 - penalty)) / 100;
    }
    
    function _calculateRewardAmplifier() private view returns (uint256) {
        uint256 amplifierDecrease = (block.timestamp - genesisTs) /
            SECONDS_IN_DAY;
        if (amplifierDecrease < REWARD_AMPLIFIER_START) {
            return
                MathUpgradeable.max(
                    REWARD_AMPLIFIER_START - amplifierDecrease,
                    REWARD_AMPLIFIER_END
                );
        } else {
            return REWARD_AMPLIFIER_END;
        }
    }
    
    function _calculateEAARate() private view returns (uint256) {
        uint256 decrease = (EAA_PM_STEP * userCount) / EAA_RANK_STEP;
        if (decrease > EAA_PM_START) return 0;
        return EAA_PM_START - decrease;
    }
    
    function getGrossReward(
        uint256 rankDelta,
        uint256 amplifier,
        uint256 term,
        uint256 eaa
    ) public pure returns (uint256) {
        int128 log128 = rankDelta.fromUInt().log_2();
        int128 reward128 = log128
            .mul(amplifier.fromUInt())
            .mul(term.fromUInt())
            .mul(eaa.fromUInt());
        return reward128.div(uint256(1_000).fromUInt()).toUInt();
    }
    
    function _penalty(uint256 secsLate) private pure returns (uint256) {
        // =MIN(2^(daysLate+3)/window-1,99)
        uint256 daysLate = secsLate / SECONDS_IN_DAY;
        if (daysLate > WITHDRAWAL_WINDOW_DAYS - 1) return MAX_PENALTY_PCT;
        uint256 penalty = (uint256(1) << (daysLate + 3)) /
            WITHDRAWAL_WINDOW_DAYS -
            1;
        return Math.min(penalty, MAX_PENALTY_PCT);
    }

    function burnFrom(
        address from,
        uint256 amount
    ) public onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    function _cleanUpUserMint() internal {
        delete userMints[msg.sender];
        activeMinters--;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
