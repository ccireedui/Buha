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

    uint public constant BUHA_MIN_STAKE = 0;

    uint public constant BUHA_MIN_BURN = 0;

    uint public constant BUHA_APY_START = 20;
    uint public constant BUHA_APY_DAYS_STEP = 90;
    uint public constant BUHA_APY_END = 2;

    mapping(address => MintInfo) public userMints;
    mapping(address => StakeInfo) public userStakes;
    mapping(address => uint) public userBurns;

    uint public genesisTs;
    uint public userCount;
    uint public activeMinters;
    uint public activeStakes;
    uint public totalBuhaStaked;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
        genesisTs = block.timestamp;
    }

    function initialize() public initializer {
        __ERC20_init("Buha Token", "BUHA");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        userCount = 1;
    }

    function startMinting(uint term) external {
        uint termSec = term * SECONDS_IN_DAY;
        require(termSec > MIN_TERM, "BUHA: Term less than min");
        require(
            termSec < _calculateMaxTerm() + 1,
            "BUHA: Term more than current max term"
        );
        require(
            userMints[msg.sender].rank == 0,
            "BUHA: Mint already in progress"
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
        emit MintStarted(msg.sender, term, userCount++);
    }

    function claim() external {
        MintInfo memory mintInfo = userMints[msg.sender];
        require(mintInfo.rank > 0, "BUHA: No mint exists");
        require(
            block.timestamp > mintInfo.maturityTs,
            "BUHA: Mint maturity not reached"
        );

        // calculate reward and mint tokens
        uint rewardAmount = _calculateMintReward(mintInfo) * 1 ether;
        _mint(msg.sender, rewardAmount);

        _cleanUpUserMint();
        emit Claimed(msg.sender, rewardAmount);
    }

    function claimEarly() external {
        MintInfo memory mintInfo = userMints[msg.sender];
        require(mintInfo.rank > 0, "BUHA: No mint exists");
        require(
            block.timestamp < mintInfo.maturityTs,
            "BUHA: Mint maturity reached"
        );

        // calculate reward and mint tokens
        uint rewardAmount = _calculateEarlyMintReward(mintInfo) * 1 ether;
        uint penalty = _earlyPenalty(mintInfo.maturityTs - block.timestamp);
        uint totalReward = (rewardAmount * (100 - penalty)) / 100;
        _mint(msg.sender, totalReward);

        _cleanUpUserMint();
        emit Claimed(msg.sender, totalReward);
    }

    function stake(uint amount, uint term) external {
        require(balanceOf(msg.sender) >= amount, "BUHA: Not enough balance");
        require(amount > BUHA_MIN_STAKE, "BUHA: Below min stake");
        require(term * SECONDS_IN_DAY > MIN_TERM, "BUHA: Below min stake term");
        require(
            term * SECONDS_IN_DAY < MAX_TERM_END + 1,
            "BUHA: Above max stake term"
        );
        require(userStakes[msg.sender].amount == 0, "BUHA: Stake exists");

        _burn(msg.sender, amount);
        _createStake(amount, term);
        emit Staked(msg.sender, amount, term);
    }

    function withdraw() external {
        StakeInfo memory userStake = userStakes[msg.sender];
        require(userStake.amount > 0, "BUHA: No stake exists");

        uint256 buhaReward = _calculateStakeReward(userStake);
        activeStakes--;
        totalBuhaStaked -= userStake.amount;

        // mint staked BUHA (+ reward)
        _mint(msg.sender, userStake.amount + buhaReward);

        emit Withdrawn(msg.sender, userStake.amount, buhaReward);
        delete userStakes[msg.sender];
    }

    function withdrawEarly() external {
        StakeInfo memory userStake = userStakes[msg.sender];
        require(userStake.amount > 0, "BUHA: No stake exists");
        require(
            block.timestamp < userStake.maturityTs,
            "BUHA: Stake maturity reached"
        );

        uint256 buhaReward = _calculateStakeReward(userStake);
        uint256 penalty = _earlyPenalty(userStake.maturityTs - block.timestamp);
        uint256 totalReward = (buhaReward * (100 - penalty)) / 100;

        activeStakes--;
        totalBuhaStaked -= userStake.amount;

        // mint staked BUHA (+ reward)
        _mint(msg.sender, userStake.amount + totalReward);

        emit Withdrawn(msg.sender, userStake.amount, totalReward);
        delete userStakes[msg.sender];
    }

    function claimAndStake(uint percentage, uint term) external {
        MintInfo memory mintInfo = userMints[msg.sender];
        require(mintInfo.rank > 0, "BUHA: No mint exists");
        require(
            block.timestamp > mintInfo.maturityTs,
            "BUHA: Mint maturity not reached"
        );
        require(
            percentage > 0 && percentage <= 100,
            "BUHA: Percentage must be between 1 and 100"
        );
        require(term * SECONDS_IN_DAY > MIN_TERM, "BUHA: Below min stake term");
        require(
            term * SECONDS_IN_DAY < MAX_TERM_END + 1,
            "BUHA: Above max stake term"
        );
        require(userStakes[msg.sender].amount == 0, "BUHA: Stake exists");

        // calculate reward and mint tokens
        uint rewardAmount = _calculateMintReward(mintInfo) * 1 ether;
        uint stakeAmount = (rewardAmount * percentage) / 100;
        uint claimingAmount = rewardAmount - stakeAmount;

        require(stakeAmount > BUHA_MIN_STAKE, "BUHA: Below min stake");

        _mint(msg.sender, claimingAmount);
        _createStake(stakeAmount, term);

        _cleanUpUserMint();
        emit Claimed(msg.sender, rewardAmount);
        emit Staked(msg.sender, stakeAmount, term);
    }

    function burn(uint amount) external {
        require(amount > BUHA_MIN_BURN, "BUHA: Below min burn limit");
        _burn(msg.sender, amount);
        userBurns[msg.sender] += amount;
    }

    function burnFrom(address from, uint amount) external {
        require(amount > BUHA_MIN_BURN, "BUHA: Below min burn limit");
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        userBurns[from] += amount;
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
        MintInfo memory mintInfo
    ) private view returns (uint) {
        uint secsLate = block.timestamp - mintInfo.maturityTs;
        uint penalty = _latePenalty(secsLate);
        uint rankDelta = MathUpgradeable.max(userCount - mintInfo.rank, 2);
        uint EAA = (1_000 + mintInfo.eaaRate);
        uint reward = getGrossReward(
            rankDelta,
            mintInfo.amplifier,
            mintInfo.term,
            EAA
        );
        return (reward * (100 - penalty)) / 100;
    }

    // TBD refactor formula
    function _calculateEarlyMintReward(
        MintInfo memory mintInfo
    ) private view returns (uint) {
        uint secsEarly = mintInfo.maturityTs - block.timestamp;
        uint penalty = _earlyPenalty(secsEarly);
        uint rankDelta = MathUpgradeable.max(userCount - mintInfo.rank, 2);
        uint EAA = (1_000 + mintInfo.eaaRate);
        uint reward = getGrossReward(
            rankDelta,
            mintInfo.amplifier,
            mintInfo.term,
            EAA
        );
        return (reward * (100 - penalty)) / 100;
    }

    function _calculateStakeReward(
        StakeInfo memory stakeInfo
    ) private view returns (uint256) {
        if (block.timestamp > stakeInfo.maturityTs) {
            uint256 rate = (stakeInfo.apy * stakeInfo.term * 1_000_000) /
                DAYS_IN_YEAR;
            return (stakeInfo.amount * rate) / 100_000_000;
        }
        return 0;
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

    function _calculateAPY() private view returns (uint256) {
        uint256 decrease = (block.timestamp - genesisTs) /
            (SECONDS_IN_DAY * BUHA_APY_DAYS_STEP);
        if (BUHA_APY_START - BUHA_APY_END < decrease) return BUHA_APY_END;
        return BUHA_APY_START - decrease;
    }

    function _earlyPenalty(uint secsEarly) private pure returns (uint) {
        // =MIN(2^(daysEarly+3)/window-1,99)
        uint daysEarly = secsEarly / SECONDS_IN_DAY;
        if (daysEarly > WITHDRAWAL_WINDOW_DAYS - 1) return MAX_PENALTY_PCT;
        uint penalty = (uint(1) << (daysEarly + 3)) /
            WITHDRAWAL_WINDOW_DAYS -
            1;
        return MathUpgradeable.min(penalty, MAX_PENALTY_PCT);
    }

    function _latePenalty(uint secsLate) private pure returns (uint) {
        // =MIN(2^(daysLate+3)/window-1,99)
        uint daysLate = secsLate / SECONDS_IN_DAY;
        if (daysLate > WITHDRAWAL_WINDOW_DAYS - 1) return MAX_PENALTY_PCT;
        uint penalty = (uint(1) << (daysLate + 3)) / WITHDRAWAL_WINDOW_DAYS - 1;
        return MathUpgradeable.min(penalty, MAX_PENALTY_PCT);
    }

    function _cleanUpUserMint() internal {
        delete userMints[msg.sender];
        activeMinters--;
    }

    function _createStake(uint amount, uint term) private {
        userStakes[msg.sender] = StakeInfo({
            term: term,
            maturityTs: block.timestamp + term * SECONDS_IN_DAY,
            amount: amount,
            apy: _calculateAPY()
        });
        activeStakes++;
        totalBuhaStaked += amount;
    }

    // Getter functions
    function getUserMint() external view returns (MintInfo memory) {
        return userMints[msg.sender];
    }

    function getUserStake() external view returns (StakeInfo memory) {
        return userStakes[msg.sender];
    }

    function getUserBurn() external view returns (uint) {
        return userBurns[msg.sender];
    }

    function getCurrentAMP() external view returns (uint) {
        return _calculateRewardAmplifier();
    }

    function getCurrentEAAR() external view returns (uint256) {
        return _calculateEAARate();
    }

    function getCurrentAPY() external view returns (uint256) {
        return _calculateAPY();
    }

    function getCurrentMaxTerm() external view returns (uint) {
        return _calculateMaxTerm();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
