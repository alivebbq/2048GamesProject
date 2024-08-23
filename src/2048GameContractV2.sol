// SPDX-License-Identifier: MIT
// 去中心化的版本，游戏逻辑在链上，前端只是调用合约的操作函数，但会非常费gas。

pragma solidity ^0.8.20;

import "./2048GameToken.sol";

contract ContractV2 {
    /* 枚举声明 */
    enum Direction {
        left,
        right,
        up,
        down
    }

    /* 结构体声明 */
    struct Players {
        address playerAddress;
        uint256 score;
    }

    /* 错误声明 */
    error GameHasBeenStarted();
    error GameNotExist();
    error GameOver();
    error NoRewardCanClaim();
    error PaymentFailed();

    /* 事件声明  */
    event StartNewGame(address indexed player);
    event EndGame(address indexed player, uint256 token_amount);
    event Slide(address indexed player, Direction direction);
    event UpdateScore(address indexed player, uint256 score);
    event SetSeason(uint256 indexed season, uint256 rewardAmount);
    event ClaimReward(address indexed player, uint256 reward);

    /* 常量 */
    uint16 public constant DOUBLE_RANDOM_TILE_FEE = 256;
    uint8 public constant REMOVE_RANDOM_TILE_FEE = 2;

    /* 公共变量 */
    uint256 public season;
    uint256 public rewardAmount;
    uint256 public lastRewardAmount;
    GameTokenContract public tokenContract;

    /* 内部变量 */

    /* 私有变量 */

    /* 映射和数组 */
    mapping(address => uint16[4][4]) public games;
    mapping(address => bool) public activeGames;
    Players[10] public top10Players;
    Players[10] public lastTop10Players;

    /* 构造函数 */
    constructor() {
        tokenContract = new GameTokenContract(address(this));
    }

    /* 修饰符 */
    modifier gameAvailable() {
        if (!activeGames[msg.sender]) revert GameNotExist();
        if (isGameOver()) revert GameOver();
        _;
    }

    modifier payment() {
        bool success = tokenContract.transferFrom(
            msg.sender,
            address(this),
            REMOVE_RANDOM_TILE_FEE / _getCoefficent()
        );
        if (!success) {
            revert PaymentFailed();
        }
        _;
    }

    /* 公共函数 */
    function startNewGame() public {
        if (activeGames[msg.sender]) {
            revert GameHasBeenStarted();
        }

        activeGames[msg.sender] = true;
        _addRandomNumber;
        _addRandomNumber;

        emit StartNewGame(msg.sender);
    }

    function endGame() public {
        if (!activeGames[msg.sender]) {
            revert GameNotExist();
        }

        activeGames[msg.sender] = false;
        delete games[msg.sender];
        uint256 point = caculatePoint();
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

    // 随机翻倍一个非零数字（道具1）
    function doubleRandomTile() public payment {
        (uint256 row, uint256 col) = _getRandomNonZeroPositions();
        games[msg.sender][row][col] *= 2;
    }

    // 随机消除一个非零数字（道具2）
    function removeRandomTile() public payment {
        (uint256 row, uint256 col) = _getRandomNonZeroPositions();
        games[msg.sender][row][col] = 0;
    }

    // 移动操作
    function slide(Direction _direction) public gameAvailable {
        if (_direction == Direction.left) {
            _slideLeft();
        } else if (_direction == Direction.right) {
            _slideRight();
        } else if (_direction == Direction.up) {
            _slideUp();
        } else if (_direction == Direction.down) {
            _slideDown();
        }

        emit Slide(msg.sender, _direction);
    }

    /* 外部函数*/

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

    function _getRandomNonZeroPositions()
        private
        view
        gameAvailable
        returns (uint256 row, uint256 col)
    {
        // 找到所有非0位置
        uint256[] memory nonZeroPositions;
        uint256 count;
        for (uint256 i = 0; i < 4; i++) {
            for (uint256 j = 0; j < 4; j++) {
                if (games[msg.sender][i][j] != 0) {
                    nonZeroPositions[count] = i * 4 + j; // 将二维位置转为一维索引
                    count++;
                }
            }
        }

        // 选择一个随机位置
        uint256 randomIndex = _getRandomNumber(count);
        uint256 position = nonZeroPositions[randomIndex];
        row = position / 4;
        col = position % 4;

        return (row, col);
    }

    // Add a random number (2 or 4) to a random empty spot on the board
    function _addRandomNumber() internal {
        uint8[2] memory emptySpot = _findEmptySpot();
        games[msg.sender][emptySpot[0]][emptySpot[1]] = uint8(
            _getRandomNumber(2) == 0 ? 2 : 4
        );
    }

    function _slideLeft() internal {
        for (uint8 i = 0; i < 4; i++) {
            uint16[4] memory row = games[msg.sender][i];
            uint16[4] memory newRow;
            uint16 k = 0;

            for (uint8 j = 0; j < 4; j++) {
                if (row[j] != 0) {
                    if (k > 0 && newRow[k - 1] == row[j]) {
                        newRow[k - 1] *= 2;
                    } else {
                        newRow[k] = row[j];
                        k++;
                    }
                }
            }

            games[msg.sender][i] = newRow;
        }
        _addRandomNumber();
    }

    function _slideRight() internal {
        for (uint8 i = 0; i < 4; i++) {
            _reverseRow(i); // 反转行
            _slideLeft(); // 调用左滑逻辑
            _reverseRow(i); // 再次反转行
        }
        _addRandomNumber();
    }

    function _slideUp() internal {
        _transposeBoard(); // 转置棋盘
        _slideLeft(); // 调用左滑逻辑
        _transposeBoard(); // 再次转置棋盘
        _addRandomNumber();
    }

    function _slideDown() internal {
        _transposeBoard(); // 转置棋盘
        for (uint8 i = 0; i < 4; i++) {
            _reverseRow(i); // 反转行
            _slideLeft(); // 调用左滑逻辑
            _reverseRow(i); // 再次反转行
        }
        _transposeBoard(); // 再次转置棋盘
        _addRandomNumber();
    }

    // 反转特定行的数组
    function _reverseRow(uint8 rowIndex) internal {
        for (uint8 i = 0; i < 2; i++) {
            (
                games[msg.sender][rowIndex][i],
                games[msg.sender][rowIndex][3 - i]
            ) = (
                games[msg.sender][rowIndex][3 - i],
                games[msg.sender][rowIndex][i]
            );
        }
    }

    // 转置棋盘（行列互换）
    function _transposeBoard() internal {
        for (uint8 i = 0; i < 4; i++) {
            for (uint8 j = i + 1; j < 4; j++) {
                (games[msg.sender][i][j], games[msg.sender][j][i]) = (
                    games[msg.sender][j][i],
                    games[msg.sender][i][j]
                );
            }
        }
    }

    /* 私有函数 */

    /* 视图函数 */
    function _getCoefficent() public view returns (uint256) {
        return (tokenContract.totalSupply() % 1_000_000) + 1;
    }

    function caculatePoint() public view returns (uint256 point) {
        for (uint8 i = 0; i < 4; i++) {
            for (uint8 j = 0; j < 4; j++) {
                point += games[msg.sender][i][j];
            }
        }
    }

    function isGameOver() public view returns (bool) {
        for (uint8 i = 0; i < 4; i++) {
            for (uint8 j = 0; j < 4; j++) {
                if (games[msg.sender][i][j] == 0) return false;
                if (
                    i < 3 &&
                    games[msg.sender][i][j] == games[msg.sender][i + 1][j]
                ) return false;
                if (
                    j < 3 &&
                    games[msg.sender][i][j] == games[msg.sender][i][j + 1]
                ) return false;
            }
        }
        return true;
    }

    function _getRandomNumber(uint256 mod) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        msg.sender
                    )
                )
            ) % mod;
    }

    function _findEmptySpot() internal view returns (uint8[2] memory) {
        uint8[16] memory emptySpots;
        uint8 count = 0;

        for (uint8 i = 0; i < 4; i++) {
            for (uint8 j = 0; j < 4; j++) {
                if (games[msg.sender][i][j] == 0) {
                    emptySpots[count] = i * 4 + j;
                    count++;
                }
            }
        }

        require(count > 0, "No empty spots available");

        uint8 randomIndex = uint8(_getRandomNumber(count));
        return [emptySpots[randomIndex] / 4, emptySpots[randomIndex] % 4];
    }
}
