// SPDX-License-Identifier: MIT
// 中心化的版本，游戏逻辑在前端，链上更关注于游戏数据保存。
pragma solidity ^0.8.20;

import "./2048GameToken.sol";

contract Contract {
    /* 结构体声明 */
    struct Players {
        address playerAddress;
        uint256 score;
    }

    /* 错误声明 */
    error GameHasBeenStarted();
    error GameNotExist();
    error NoRewardCanClaim();

    /* 事件声明  */
    event StartNewGame(address indexed player);
    event EndGame(address indexed player, uint256 token_amount);
    event UpdateScore(address indexed player, uint256 score);
    event SetSeason(uint256 indexed season, uint256 rewardAmount);
    event ClaimReward(address indexed player, uint256 reward);

    /* 公共变量 */
    uint256 public season; // 当前赛季
    uint256 public rewardAmount; // 当前赛季奖池，前10玩家平分
    uint256 public lastRewardAmount; // 上赛季奖池
    GameTokenContract public tokenContract; // 代币合约地址，部署游戏合约的时候同时部署代币合约

    /* 私有变量 */
    address private verifier; // 拥有更新棋盘权限的地址

    /* 映射和数组 */
    mapping(address => uint16[4][4]) public games; // 存储玩家地址的棋盘
    mapping(address => bool) public activeGames; // 存储玩家地址是否有正在进行的游戏
    Players[10] public top10Players; // 当前赛季前10玩家排行榜，包括地址和对应的分数
    Players[10] public lastTop10Players; // 上赛季排行榜

    /* 构造函数 */
    constructor() {
        tokenContract = new GameTokenContract(address(this));
        verifier = msg.sender;
    }

    /* 修饰符 */
    modifier GameExist() {
        if (!activeGames[msg.sender]) {
            revert GameNotExist();
        }
        _;
    }

    /* 公共函数 */
    // 开始新游戏。activeGames返回false时需首先调用，后续的游戏则用updateBoard更新棋盘。
    function startNewGame(
        uint16[4][4] calldata newBoard,
        bytes calldata signature
    ) public {
        if (activeGames[msg.sender]) {
            revert GameHasBeenStarted();
        }

        activeGames[msg.sender] = true;
        updateBoard(newBoard, signature);

        emit StartNewGame(msg.sender);
    }

    // 更新棋盘。可用于更新玩家的普通移动，也可用于更新玩家购买道具后的变化，payable，可以接收玩家购买道具时消耗的token。
    function updateBoard(
        uint16[4][4] calldata newBoard,
        bytes calldata signature
    ) public payable GameExist {
        // 计算新棋盘的哈希
        bytes32 messageHash = keccak256(abi.encodePacked(newBoard));

        // 验证签名
        require(
            _recoverSigner(messageHash, signature) == verifier,
            "Invalid signature"
        );

        // 更新棋盘状态
        games[msg.sender] = newBoard;
    }

    // 结束游戏并获得代币
    function endGame() public GameExist {
        activeGames[msg.sender] = false;
        delete games[msg.sender];
        uint256 point = _caculatePoint();
        uint256 coefficent = _getCoefficent();
        uint256 availableAmount = point / coefficent;

        if (point > top10Players[top10Players.length - 1].score) {
            _updateScore(msg.sender, point);
        }

        tokenContract.mint(msg.sender, availableAmount);

        emit EndGame(msg.sender, availableAmount);
    }

    // 设置新赛季并结算旧赛季,玩家需在新赛季结束前cliam上赛季奖励，否则奖励将失效
    function setSeason(uint256 _rewardAmount) public {
        season++;
        lastRewardAmount = rewardAmount;
        rewardAmount = _rewardAmount;
        lastTop10Players = top10Players;
        for (uint256 i = 0; i < top10Players.length; i++) {
            top10Players[i] = Players(address(0), 0);
        }

        emit SetSeason(season, _rewardAmount);
    }

    function claimReward() public {
        uint256 length = top10Players.length;
        for (uint256 i = 0; i < length; i++) {
            if (top10Players[i].playerAddress == msg.sender) {
                uint256 reward = lastRewardAmount / length;
                tokenContract.mint(msg.sender, reward);
                emit ClaimReward(msg.sender, reward);
                return;
            }
        }

        revert NoRewardCanClaim();
    }

    /* 内部函数 */
    // 更新玩家的分数并更新排行榜
    function _updateScore(address player, uint256 newScore) internal {
        bool playerExists = false;
        Players[10] memory _top10Players = top10Players;

        // 检查玩家是否已经在前 10 名中
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
            top10Players[_top10Players.length - 1] = Players(player, newScore); // 将玩家放入第 10 位
        }

        // 对排行榜进行排序
        _sortLeaderboard();

        emit UpdateScore(msg.sender, newScore);
    }

    // 冒泡排序对排行榜进行排序
    function _sortLeaderboard() internal {
        Players[10] memory _top10Players = top10Players;

        for (uint256 i = 0; i < _top10Players.length - 1; i++) {
            for (uint256 j = 0; j < _top10Players.length - 1 - i; j++) {
                if (_top10Players[j].score < _top10Players[j + 1].score) {
                    top10Players[j] = top10Players[j + 1];
                    top10Players[j + 1] = _top10Players[j];
                }
            }
        }
    }

    /* 视图函数 */
    function _getCoefficent() internal view returns (uint256) {
        return (tokenContract.totalSupply() % 1_000_000) + 1;
    }

    function _caculatePoint() internal view returns (uint256 point) {
        for (uint8 i = 0; i < 4; i++) {
            for (uint8 j = 0; j < 4; j++) {
                point += games[msg.sender][i][j];
            }
        }
    }

    function _recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address) {
        bytes32 ethSignedMessageHash = _getEthSignedMessageHash(messageHash);
        return recover(ethSignedMessageHash, signature);
    }

    function _getEthSignedMessageHash(
        bytes32 messageHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    messageHash
                )
            );
    }

    function recover(
        bytes32 ethSignedMessageHash,
        bytes memory signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    function _splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        return (r, s, v);
    }
}
