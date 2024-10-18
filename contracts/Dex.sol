// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract BaseUpgradeable {
    // Errors
    string internal constant ErrNotsupportedToken = "ErrNotsupportedToken";
    string internal constant ErrLengthMismatch = "ErrLengthMismatch";
    string internal constant ErrNotEnoughBalance = "ErrNotEnoughBalance";
    string internal constant ErrNotOrderExpired = "ErrNotOrderExpired";
    string internal constant ErrInvalidSigner = "ErrInvalidSigner";
    string internal constant ErrOrderAlreadyFilled = "ErrOrderAlreadyFilled";

    string public name;
    uint256 internal INITIAL_CHAIN_ID;
    bytes32 internal INITIAL_DOMAIN_SEPARATOR;
    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "OrderPermit(address sender,int8 side,uint256 price,uint256 amount,address baseToken,address quoteToken,uint256 nonce,uint256 expiration)"
        );

    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public userNonces;
    mapping(address => mapping(address => uint256)) internal userBalances; // user => token => amount
    mapping(address => mapping(uint256 => bool)) internal filledOrders; // user => nonce => bool

    // Events
    event OrderMatched(Trade[] trades, Order remainingOrder);
    event Deposited(address sender, address token, uint256 amount);
    event Withdrew(address sender, address token, uint256 amount);
    event SupportedTokenUpdated(address[] tokens, bool[] values);

    struct Order {
        address sender;
        Side side;
        uint256 price;
        uint256 amount;
        address baseToken;
        address quoteToken;
        uint256 nonce;
        uint256 expiration;
    }
    struct Trade {
        Order takerOrder;
        Order makerOrder;
        uint256 amount;
        uint256 price;
    }

    enum Side {
        SELL, // 0
        BUY // 1
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _initializeEIP712() internal {
        name = "Dex";
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    function splitSignature(
        bytes memory sig
    ) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract Dex is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    BaseUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    modifier onlySupportedToken(address _token) {
        require(supportedTokens[_token], ErrNotsupportedToken);
        _;
    }

    modifier onlyValidBalance(
        address _user,
        address _token,
        uint256 _amount
    ) {
        require(userBalances[_user][_token] >= _amount, ErrNotEnoughBalance);
        _;
    }

    modifier onlyValidOrder(address _user, uint256 _nonce) {
        require(!filledOrders[_user][_nonce], ErrOrderAlreadyFilled);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __Pausable_init();
        _initializeEIP712();
    }

    // Owner functions
    function setSupportedTokens(
        address[] calldata _tokens,
        bool[] calldata _values
    ) external onlyOwner {
        require(_tokens.length == _values.length, ErrLengthMismatch);

        for (uint256 i = 0; i < _tokens.length; i++) {
            supportedTokens[_tokens[i]] = _values[i];
        }

        emit SupportedTokenUpdated(_tokens, _values);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // User functions
    function deposit(
        address _token,
        uint256 _amount
    ) external onlySupportedToken(_token) {
        IERC20Upgradeable(_token).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        userBalances[msg.sender][_token] += _amount;

        emit Deposited(msg.sender, _token, _amount);
    }

    function withdraw(
        address _token,
        uint256 _amount
    )
        external
        onlySupportedToken(_token)
        onlyValidBalance(msg.sender, _token, _amount)
    {
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
        userBalances[msg.sender][_token] -= _amount;

        emit Withdrew(msg.sender, _token, _amount);
    }

    function withdrawAssets(
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external {
        require(_tokens.length == _amounts.length, ErrLengthMismatch);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address _token = _tokens[i];
            uint256 _amount = _amounts[i];

            require(supportedTokens[_token], ErrNotsupportedToken);
            require(
                userBalances[msg.sender][_token] >= _amount,
                ErrNotEnoughBalance
            );

            IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
            userBalances[msg.sender][_token] -= _amount;

            emit Withdrew(msg.sender, _token, _amount);
        }
    }

    function verifyOrderSig(Order memory _order, bytes memory _sig) public {
        require(_order.expiration >= block.timestamp, ErrNotOrderExpired);

        (bytes32 _r, bytes32 _s, uint8 _v) = splitSignature(_sig);

        int8 side = 0; // sell
        if (_order.side == Side.BUY) {
            side = 1;
        }

        // check if the signature is valid
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            ORDER_TYPEHASH,
                            _order.sender,
                            side,
                            _order.price,
                            _order.amount,
                            _order.baseToken,
                            _order.quoteToken,
                            userNonces[_order.sender]++,
                            _order.expiration
                        )
                    )
                )
            );

            address recoveredAddress = ecrecover(digest, _v, _r, _s);

            require(
                recoveredAddress != address(0) &&
                    recoveredAddress == _order.sender,
                ErrInvalidSigner
            );
        }
    }

    function verifyOrderSigs(
        Order[] memory _orders,
        bytes[] memory _sigs
    ) public {
        require(_orders.length == _sigs.length, ErrLengthMismatch);

        for (uint256 i = 0; i < _orders.length; i++) {
            Order memory order = _orders[i];
            bytes memory sig = _sigs[i];

            require(order.expiration >= block.timestamp, ErrNotOrderExpired);
            (bytes32 _r, bytes32 _s, uint8 _v) = splitSignature(sig);
            int8 side = 0; // sell
            if (order.side == Side.BUY) {
                side = 1;
            }

            // check if the signature is valid
            unchecked {
                bytes32 digest = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                ORDER_TYPEHASH,
                                order.sender,
                                side,
                                order.price,
                                order.amount,
                                order.baseToken,
                                order.quoteToken,
                                userNonces[order.sender]++,
                                order.expiration
                            )
                        )
                    )
                );

                address recoveredAddress = ecrecover(digest, _v, _r, _s);

                require(
                    recoveredAddress != address(0) &&
                        recoveredAddress == order.sender,
                    ErrInvalidSigner
                );
            }
        }
    }

    function verifyFilledOrders(Order[] memory _orders) public view {
        for (uint256 i = 0; i < _orders.length; i++) {
            Order memory order = _orders[i];
            require(
                !filledOrders[order.sender][order.nonce],
                ErrOrderAlreadyFilled
            );
        }
    }

    function matchOrders(
        Order memory _makerOrder,
        Order memory _takerOrder,
        bytes memory _makerOrderSig,
        bytes memory _takerOrderSig
    )
        public
        onlyOwner
        onlyValidOrder(_makerOrder.sender, _makerOrder.nonce)
        onlyValidOrder(_takerOrder.sender, _takerOrder.nonce)
    {
        // verify
        verifyOrderSig(_makerOrder, _makerOrderSig);
        verifyOrderSig(_takerOrder, _takerOrderSig);
        uint256 tradeAmount;
        uint256 tradePrice;
        Trade[] memory trades = new Trade[](1);
        Order memory remainingOrder;
        // match
        if (_makerOrder.side == Side.BUY && _takerOrder.side == Side.SELL) {
            // order shouldn't match B: 10 - S: 12
            if (_makerOrder.price < _takerOrder.price) {
                return;
            }
            tradePrice = _takerOrder.price;
        }
        if (_makerOrder.side == Side.SELL && _takerOrder.side == Side.BUY) {
            // order shouldn't match S: 10 - B: 8
            if (_makerOrder.price > _takerOrder.price) {
                return;
            }
            tradePrice = _takerOrder.price;
        }

        if (_makerOrder.amount > _takerOrder.amount) {
            tradeAmount = _takerOrder.amount;
            remainingOrder = _makerOrder;
            remainingOrder.amount = _makerOrder.amount - tradeAmount;
            filledOrders[_takerOrder.sender][_takerOrder.nonce] = true;
        } else {
            tradeAmount = _makerOrder.amount;
            remainingOrder = _takerOrder;
            remainingOrder.amount = _takerOrder.amount - tradeAmount;
            filledOrders[_makerOrder.sender][_makerOrder.nonce] = true;
        }

        trades[0] = Trade(_takerOrder, _makerOrder, tradeAmount, tradePrice);
        emit OrderMatched(trades, remainingOrder);
    }

    function matchMarketOrders(
        Order[] memory _makerOrders,
        Order memory _takerOrder,
        bytes[] memory _makerOrderSigs,
        bytes memory _takerOrderSig
    ) public onlyOwner onlyValidOrder(_takerOrder.sender, _takerOrder.nonce) {
        // verify
        verifyOrderSig(_takerOrder, _takerOrderSig);
        verifyOrderSigs(_makerOrders, _makerOrderSigs);
        verifyFilledOrders(_makerOrders);
        Trade[] memory trades = new Trade[](_makerOrders.length);
        Order memory remainingOrder;
        uint256 remainingAmount = _takerOrder.amount;

        for (uint256 i = 0; i < _makerOrders.length; i++) {
            Order memory makerOrder = _makerOrders[i];
            if (remainingAmount == 0) {
                return;
            }

            if (remainingAmount > makerOrder.amount) {
                remainingAmount -= makerOrder.amount;
                filledOrders[makerOrder.sender][makerOrder.nonce] = true;
                trades[i] = Trade(
                    _takerOrder,
                    makerOrder,
                    makerOrder.amount,
                    makerOrder.price
                );
            } else if (remainingAmount == makerOrder.amount) {
                remainingAmount -= makerOrder.amount;
                filledOrders[_takerOrder.sender][_takerOrder.nonce] = true;
                filledOrders[makerOrder.sender][makerOrder.nonce] = true;

                trades[i] = Trade(
                    _takerOrder,
                    makerOrder,
                    remainingAmount,
                    makerOrder.price
                );
            } else {
                // remainingAmount < makerOrder.price
                filledOrders[_takerOrder.sender][_takerOrder.nonce] = true;

                trades[i] = Trade(
                    _takerOrder,
                    makerOrder,
                    remainingAmount,
                    makerOrder.price
                );
                remainingOrder = makerOrder;
                remainingOrder.amount = makerOrder.amount - remainingAmount;
                remainingAmount = 0;
            }
        }

        emit OrderMatched(trades, remainingOrder);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}
