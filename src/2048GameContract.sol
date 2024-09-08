// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./2048GameToken.sol";
import "./2048NFT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Contract is Ownable {
    /* 结构体声明 */
    struct Players {
        address playerAddress;
        uint256 score;
    }

    /* 错误声明 */
    error NoRewardCanClaim();

    /* 事件声明  */
    event EndGame(address indexed player, uint256 token_amount);
    event UpdateTop10Players(address indexed player, uint256 score);
    event SetSeason(uint256 indexed season, uint256 rewardAmount);
    event ClaimReward(address indexed player, uint256 reward);
    event MintNFT(address indexed player, uint256 indexed scoreTier);

    /* 公共变量 */
    uint256 public season; // 当前赛季
    uint256 public rewardAmount; // 当前赛季奖池，排行榜的玩家赛季结束时可获得1/10
    uint256 public lastRewardAmount; // 上赛季奖池
    GameTokenContract public tokenContract; // 代币合约地址，部署游戏合约的时候同时部署代币合约
    AchivementNFT public nftContract;
    IERC20 public croakToken =
        IERC20(0xaCb54d07cA167934F57F829BeE2cC665e1A5ebEF);
    /* 映射和数组 */
    Players[10] private top10Players; // 当前赛季前10玩家排行榜，包括地址和对应的分数
    Players[10] private lastTop10Players; // 上赛季排行榜
    mapping(address => uint16[4][4]) private games; // 存储玩家地址的棋盘
    mapping(address => uint256) public accumulatedScores; // 累计总得分(不含当前游戏得分)
    mapping(address => uint256) public scores; // 当前游戏得分，如果没有进行中的游戏则为0

    /* 构造函数 */
    constructor() Ownable(msg.sender) {
        tokenContract = new GameTokenContract();
        nftContract = new AchivementNFT();
    }

    /* 公共函数 */
    // 保存棋盘。可用于更新玩家的普通移动，也可用于更新玩家购买道具后的变化，payable，可以接收玩家购买道具时消耗的token。
    function updateBoard(
        uint16[4][4] calldata newBoard,
        uint256 score
    ) public payable {
        scores[msg.sender] = score;
        games[msg.sender] = newBoard;
    }

    // 结束游戏并获得代币
    function endGame(uint256 score) public {
        scores[msg.sender] = 0;
        accumulatedScores[msg.sender] += score;
        delete games[msg.sender];
        uint256 availableAmount = (score * 1e18) / getCoefficent();

        if (score > top10Players[top10Players.length - 1].score) {
            _updateTop10Players(msg.sender, accumulatedScores[msg.sender]);
        }

        tokenContract.mint(msg.sender, availableAmount);

        emit EndGame(msg.sender, availableAmount);
    }

    // 设置新赛季并结算旧赛季,玩家需在新赛季结束前cliam上赛季奖励，否则奖励将失效。单位ether
    function setSeason(uint256 _rewardAmount) public onlyOwner {
        season++;
        lastRewardAmount = rewardAmount;
        rewardAmount = _rewardAmount;
        lastTop10Players = top10Players;

        for (uint256 i = 0; i < top10Players.length; i++) {
            top10Players[i] = Players(address(0), 0);
        }

        require(
            croakToken.transferFrom(msg.sender, address(this), _rewardAmount),
            "Transfer failed"
        );

        emit SetSeason(season, _rewardAmount);
    }

    function claimReward() public {
        uint256 length = top10Players.length;
        for (uint256 i = 0; i < length; i++) {
            if (lastTop10Players[i].playerAddress == msg.sender) {
                lastTop10Players[i] = Players(address(0), 0);
                uint256 reward = lastRewardAmount / length;

                require(
                    croakToken.transfer(msg.sender, reward),
                    "Transfer failed"
                );

                emit ClaimReward(msg.sender, reward);
                return;
            }
        }

        revert NoRewardCanClaim();
    }

    function mintNFT(uint256 scoreTier) public {
        uint256 score = accumulatedScores[msg.sender];
        if (scoreTier == 1) {
            require(score > 100000);
        } else if (scoreTier == 2) {
            require(score > 200000);
        } else if (scoreTier == 3) {
            require(score > 500000);
        } else if (scoreTier == 4) {
            require(score > 2000000);
        } else {
            revert("error score tier!");
        }

        nftContract.mintNFT(msg.sender, scoreTier);
        emit MintNFT(msg.sender, scoreTier);
    }

    /* 内部函数 */
    // 更新玩家的分数并更新排行榜
    function _updateTop10Players(address player, uint256 newScore) internal {
        bool playerExists = false;
        Players[10] memory _top10Players = top10Players;

        for (uint256 i = 0; i < _top10Players.length; i++) {
            if (
                _top10Players[i].playerAddress == player &&
                _top10Players[i].score < newScore
            ) {
                top10Players[i].score = newScore;
                playerExists = true;
                break;
            }
        }

        if (!playerExists) {
            top10Players[_top10Players.length - 1] = Players(player, newScore);
        }

        _sortLeaderboard();

        emit UpdateTop10Players(msg.sender, newScore);
    }

    function _sortLeaderboard() internal {
        Players[10] memory _top10Players = top10Players;

        for (uint256 i = 0; i < _top10Players.length - 1; i++) {
            for (uint256 j = 0; j < _top10Players.length - 1 - i; j++) {
                if (_top10Players[j].score < _top10Players[j + 1].score) {
                    Players memory temp = _top10Players[j];
                    _top10Players[j] = _top10Players[j + 1];
                    _top10Players[j + 1] = temp;
                }
            }
        }

        for (uint256 i = 0; i < top10Players.length; i++) {
            top10Players[i] = _top10Players[i];
        }
    }

    /* 视图函数 */
    function getCoefficent() public view returns (uint256) {
        return (tokenContract.totalSupply() / 1e24) + 1;
    }

    // 获取玩家已存在的棋盘。游戏若未开始返回的则是个4X4的全0数组
    function getGameBoard(
        address user
    ) public view returns (uint16[4][4] memory) {
        return games[user];
    }

    function getTop10Players() public view returns (Players[10] memory) {
        Players[10] memory top10 = top10Players;
        for (uint256 i = 0; i < 10; i++) {
            top10[i] = top10Players[i];
        }

        return top10;
    }

    function getPlayerAllNFT(
        address playerAddress
    ) public view returns (string[] memory) {
        return nftContract.getPlayerOwnedScoreTier(playerAddress);
    }

    function getUserTierAndMintStatus(
        address playerAddress
    ) public view returns (uint256, bool) {
        uint256 accumulatedScore = accumulatedScores[playerAddress];
        uint256 tier = 0;
        if (100000 < accumulatedScore && accumulatedScore < 200000) {
            tier = 1;
        } else if (200000 < accumulatedScore && accumulatedScore < 500000) {
            tier = 2;
        } else if (500000 < accumulatedScore && accumulatedScore < 2000000) {
            tier = 3;
        } else if (2000000 < accumulatedScore) {
            tier = 4;
        }
        string[] memory playerAllNFT = getPlayerAllNFT(playerAddress);
        return (tier, tier > playerAllNFT.length);
    }
}
