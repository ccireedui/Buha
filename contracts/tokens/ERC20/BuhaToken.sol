// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IBuhaToken.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";

contract BuhaToken is
    IBuhaToken,
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using MathUpgradeable for uint;
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    struct MintInfo {
        address user;
        uint term;
        uint maturityTs;
        uint rank;
        uint amplifier;
        uint eaaRate;
    }

    struct StakeInfo {
        uint term;
        uint maturityTs;
        uint amount;
        uint apy;
    }

    // PUBLIC CONSTANTS

    uint public constant SECONDS_IN_DAY = 3_600 * 24;
    uint public constant DAYS_IN_YEAR = 365;

    uint public constant GENESIS_RANK = 1;

    uint public constant MIN_TERM = 1 * SECONDS_IN_DAY - 1;
    uint public constant MAX_TERM_START = 100 * SECONDS_IN_DAY;
    uint public constant MAX_TERM_END = 1_000 * SECONDS_IN_DAY;
    uint public constant TERM_AMPLIFIER = 15;
    uint public constant TERM_AMPLIFIER_THRESHOLD = 5_000;
    uint public constant REWARD_AMPLIFIER_START = 3_000;
    uint public constant REWARD_AMPLIFIER_END = 1;
    uint public constant EAA_PM_START = 100;
    uint public constant EAA_PM_STEP = 1;
    uint public constant EAA_RANK_STEP = 100_000;
    uint public constant WITHDRAWAL_WINDOW_DAYS = 7;
    uint public constant MAX_PENALTY_PCT = 99;

    uint public userCount;

    mapping(address => MintInfo) public userMints;

    mapping(address => StakeInfo) public userStakes;

    uint public immutable genesisTs;
    uint public activeMinters;
    uint public activeStakes;
    uint public totalXenStaked;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
        genesisTs = block.timestamp;
    }

    function initialize() public initializer {
        __ERC20_init("BuhaToken", "BUHA");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
    }

    function mint(uint term) public {
        uint termSec = term * SECONDS_IN_DAY;
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
            rank: userCount,
            amplifier: _calculateRewardAmplifier(),
            eaaRate: _calculateEAARate()
        });
        userMints[msg.sender] = mintInfo;
        activeMinters++;
        emit Minted(msg.sender, term, userCount++);
    }

    function _calculateMaxTerm() private view returns (uint) {
        if (userCount > TERM_AMPLIFIER_THRESHOLD) {
            uint delta = userCount
                .fromUInt()
                .log_2()
                .mul(TERM_AMPLIFIER.fromUInt())
                .toUInt();
            uint newMax = MAX_TERM_START + delta * SECONDS_IN_DAY;
            return MathUpgradeable.min(newMax, MAX_TERM_END);
        }
        return MAX_TERM_START;
    }

    function _calculateMintReward(
        uint cRank,
        uint term,
        uint32 maturityTs,
        uint amplifier,
        uint eeaRate
    ) private view returns (uint) {
        uint secsLate = block.timestamp - maturityTs;
        uint penalty = _penalty(secsLate);
        uint rankDelta = MathUpgradeable.max(userCount - cRank, 2);
        uint EAA = (1_000 + eeaRate);
        uint reward = getGrossReward(rankDelta, amplifier, term, EAA);
        return (reward * (100 - penalty)) / 100;
    }

    function _calculateRewardAmplifier() private view returns (uint) {
        uint amplifierDecrease = (block.timestamp - genesisTs) / SECONDS_IN_DAY;
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

    function _calculateEAARate() private view returns (uint) {
        uint decrease = (EAA_PM_STEP * userCount) / EAA_RANK_STEP;
        if (decrease > EAA_PM_START) return 0;
        return EAA_PM_START - decrease;
    }

    function getGrossReward(
        uint rankDelta,
        uint amplifier,
        uint term,
        uint eaa
    ) public pure returns (uint) {
        int128 log128 = rankDelta.fromUInt().log_2();
        int128 reward128 = log128
            .mul(amplifier.fromUInt())
            .mul(term.fromUInt())
            .mul(eaa.fromUInt());
        return reward128.div(uint(1_000).fromUInt()).toUInt();
    }

    function _penalty(uint secsLate) private pure returns (uint) {
        // =MIN(2^(daysLate+3)/window-1,99)
        uint daysLate = secsLate / SECONDS_IN_DAY;
        if (daysLate > WITHDRAWAL_WINDOW_DAYS - 1) return MAX_PENALTY_PCT;
        uint penalty = (uint(1) << (daysLate + 3)) / WITHDRAWAL_WINDOW_DAYS - 1;
        return MathUpgradeable.min(penalty, MAX_PENALTY_PCT);
    }

    function burnFrom(address from, uint amount) public onlyRole(BURNER_ROLE) {
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
