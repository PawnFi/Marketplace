// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20Upgradeable, SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IRoyaltyFeeManager.sol";
import "./libraries/TransferHelper.sol";

/**
 * @title Pawnfi's PawnfiApproveTrade Contract
 * @author Pawnfi
 */
contract PawnfiApproveTrade is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ECDSAUpgradeable for bytes32;

    // Identifier of ERC721
    address private constant ERC721 = 0x0000000000000000000000000000000000000721;

    // Identifier of ERC1155
    address private constant ERC1155 = 0x0000000000000000000000000000000000001155;

    // Denominator, used for calculating percentage
    uint256 private constant DENOMINATOR = 10000;

    // keccak256("Order(address maker,address taker,address collection,address assetClass,address currency,uint256 price,uint256 tokenId,uint256 amount,uint256 nonce,uint256 deadline)")
    bytes32 private constant ORDER_HASH = 0x48f7b7c3c4793a1257b8364652c890aa9e9afbe487bf917404e1f151e67a1e8b;

    /// @notice WETH contract address
    address public WETH;

    /// @notice Platform fee
    uint256 public platformFee;

    /// @notice Fee receiver
    address payable public protocolFeeReceiver;

    /// @notice ERC721 transfer manager address
    address public transferManager;

    bytes32 public DOMAIN_SEPARATOR;

    /**
     * @notice Order info
     * @member maker maker of the order
     * @member taker taker of the order
     * @member collection collection address
     * @member assetClass asset class (e.g., ERC721)
     * @member currency currency (e.g., WETH)
     * @member price price (used as )
     * @member tokenId id of the token
     * @member amount amount of tokens to sell/purchase (must be 1 for ERC721, 1+ for ERC1155)
     * @member deadline deadline in timestamp - 0 for no expiry
     * @member sig Signature
     */
    struct Order {
        address maker;
        address taker;
        address collection;
        address assetClass;
        address currency;
        uint256 price;
        uint256 tokenId;
        uint256 amount;
        uint256 deadline;
        bytes sig;
    }

    /// @notice Record the nonce for the address signature handling listings and offers
    mapping(address => uint256) public nonces;

    /// @notice Identifier of order cancellation or success
    mapping(bytes32 => bool) public cancelledOrFinalized;

    /// @notice Royalty fee manager address
    address public royaltyFeeManager;

    /// @notice Emitted when update fee receiver
    event ProtocolFeeReceiverUpdate(address protocolFeeReceiver);

    /// @notice Emitted when update platform fee rate
    event PlatformFeeUpdate(uint256 platformFee);

    /// @notice Emitted when update royalty manager address
    event RoyaltyFeeManagerUpdate(address royaltyFeeManager);

    /// @notice Emitted when nonce increases
    event NonceIncremented(address indexed maker, uint256 nonce);

    /// @notice Emitted when cancel order
    event CancelOrders(bytes32 hash);

    /// @notice Emitted when cancel multiple orders
    event CancelMultipleOrders(bytes32[] hashs);

    /// @notice Emitted when offer is taken
    event TakerAsk(address indexed buyer, address indexed seller, bytes32 orderHash, address currency, address assetClass, address collection, address royaltyReceiver, uint256 tokenId, uint256 amount, uint256 price, uint256 fee, uint256 royaltyAmount);

    /// @notice Emitted when listing is matched
    event TakerBid(address indexed buyer, address indexed seller, bytes32 orderHash, address currency, address assetClass, address collection, address royaltyReceiver, uint256 tokenId, uint256 amount, uint256 price, uint256 fee, uint256 royaltyAmount);

    /**
     * @notice Initialize contract parameters - only execute once
     * @param owner_ Owner address
     * @param WETH_ WETH address
     * @param protocolFeeReceiver_ Fee receiver
     * @param transferManager_ ERC721 transfer manager address
     * @param royaltyFeeManager_ Royalty fee manager address
     * @param platformFee_ Platform fee
     */
    function initialize(address owner_, address WETH_, address payable protocolFeeReceiver_, address transferManager_, address royaltyFeeManager_, uint256 platformFee_) external initializer {
        _transferOwnership(owner_);
        __ReentrancyGuard_init();
        WETH = WETH_;
        protocolFeeReceiver = protocolFeeReceiver_;
        transferManager = transferManager_;
        royaltyFeeManager = royaltyFeeManager_;
        platformFee = platformFee_;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("PawnfiApproveTrade")),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    receive() external payable {}

    /**
     * @notice Set new fee receiver - exclusive to owner
     * @param protocolFeeReceiver_ Fee receiver
     */
    function setProtocolFeeReceiver(address payable protocolFeeReceiver_) external onlyOwner {
        protocolFeeReceiver = protocolFeeReceiver_;
        emit ProtocolFeeReceiverUpdate(protocolFeeReceiver_);
    }

    /**
     * @notice Set new platform fee - exclusive to owner
     * @param newPlatformFee Plarform fee
     */
    function setPlatformFee(uint256 newPlatformFee) external onlyOwner {
        require(newPlatformFee < DENOMINATOR);
        platformFee = newPlatformFee;
        emit PlatformFeeUpdate(newPlatformFee);
    }

    /**
     * @notice Set new royalty fee manager address - exclusive to owner
     * @param newRoyaltyFeeManager Royalty fee manager address
     */
    function setRoyaltyFeeManager(address newRoyaltyFeeManager) external onlyOwner {
        royaltyFeeManager = newRoyaltyFeeManager;
        emit RoyaltyFeeManagerUpdate(newRoyaltyFeeManager);
    }

    /**
     * @notice Increase nonce，cancel all listings and offers
     */
    function incrementNonce() external nonReentrant onlyEOA {
        uint256 newNonce = ++nonces[msg.sender];
        emit NonceIncremented(msg.sender, newNonce);
    }

    /**
     * @notice Cancel multiple orders
     * @param orders Order array
     */
	function cancelMultipleOrders(Order[] memory orders) external nonReentrant onlyEOA {
        bytes32[] memory hashs = new bytes32[](orders.length);
		for(uint i = 0; i < orders.length; i++) {
			hashs[i] = _cancelOrder(orders[i]);
		}
        emit CancelMultipleOrders(hashs);
	}

    /**
     * @notice Cancel single order
     * @param order Order
     */
    function cancelOrder(Order memory order) public nonReentrant onlyEOA {
        bytes32 orderHash = _cancelOrder(order);

        emit CancelOrders(orderHash);
    }

    /**
     * @notice Cancel single order
     * @param order order
     * @return bytes32 order hash
     */
    function _cancelOrder(Order memory order) private returns (bytes32) {
        bytes32 orderHash = hashOrder(order);
        require(msg.sender == order.maker, "Not maker of the order");
        require(!cancelledOrFinalized[orderHash], "duplicate cancel");

        cancelledOrFinalized[orderHash] = true;
        return orderHash;
    }

    /**
     * @notice Buyer confirms the order by checking seller's signature
     * @param buy Buyer order info
     * @param sell Seller order info
     */
    function matchAskWithTakerBid(Order memory buy, Order memory sell) public payable nonReentrant onlyEOA {
        require(buy.maker == msg.sender);
        require(_ordersCanMatch(buy, sell), "Failed to match");

        bytes32 orderHash = _validate(sell);
        cancelledOrFinalized[orderHash] = true;

        (uint256 fee, uint256 royaltyAmount, address royaltyReceiver) = _swapAssets(buy.maker, sell.maker, sell);

        emit TakerBid(buy.maker, sell.maker, orderHash, sell.currency, sell.assetClass, sell.collection, royaltyReceiver, sell.tokenId, sell.amount, sell.price, fee, royaltyAmount);
    }

    /**
     * @notice Seller confirms the order (offer taken)
     * @param buy Buyer order info
     * @param sell Seller order info
     */
    function matchBidWithTakerAsk(Order memory buy, Order memory sell) public nonReentrant onlyEOA {
        require(sell.maker == msg.sender);
        require(_ordersCanMatch(buy, sell), "Failed to match");

        bytes32 orderHash = _validate(buy);
        cancelledOrFinalized[orderHash] = true;

        (uint256 fee, uint256 royaltyAmount, address royaltyReceiver) = _swapAssets(buy.maker, sell.maker, sell);

        emit TakerAsk(buy.maker, sell.maker, orderHash, sell.currency, sell.assetClass, sell.collection, royaltyReceiver, sell.tokenId, sell.amount, sell.price, fee, royaltyAmount);
    }

    /**
     * @notice Exchange assets
     * @param maker Buyer
     * @param taker Seller
     * @param order Order info
     * @return fee PLatform fee
     * @return royaltyAmount Royalty amount
     * @return royaltyReciever Royalty receiver
     */
    function _swapAssets(address maker, address taker, Order memory order) private returns (uint256 fee, uint256 royaltyAmount, address royaltyReciever) {
        require(order.assetClass == ERC721, "Only support ERC721 assetClass");
        fee = order.price * platformFee / DENOMINATOR;
        (royaltyReciever, royaltyAmount) = IRoyaltyFeeManager(royaltyFeeManager).calculateRoyaltyFeeAndGetRecipient(order.collection, order.tokenId, order.price);
        uint256 value = order.price - fee - royaltyAmount;

        if (msg.value > 0) {
            require(order.currency == WETH && msg.value == order.price, "Failed transfer");
        } else {
            IERC20Upgradeable(order.currency).safeTransferFrom(maker, address(this), order.price);
        }
        
        _transferAsset(order.currency, royaltyReciever, royaltyAmount);
        _transferAsset(order.currency, protocolFeeReceiver, fee);
        _transferAsset(order.currency, taker, value);

        TransferHelper.transferInNonFungibleToken(transferManager, order.collection, taker, maker, order.tokenId);
    }

    /**
     * @notice Send ERC20 asset
     * @param token token address
     * @param recipient Receiver
     * @param amount Sent amount
     */
    function _transferAsset(address token, address recipient, uint256 amount) private {
        if(recipient != address(0) && amount>0){
            if(token == WETH) {
                uint256 bal = address(this).balance;
                if(bal < amount) {
                    IWETH(WETH).withdraw(amount - bal);
                }
                payable(recipient).transfer(amount);
            } else {
                IERC20Upgradeable(token).safeTransfer(recipient, amount);
            }
        }
    }

    /**
     * @notice Get hash of order information
     * @param order Order info
     * @return orderHash order hash
     */
    function hashOrder(Order memory order) public view returns (bytes32 orderHash) {
        bytes32 structHash = keccak256(abi.encode(
            ORDER_HASH,
            order.maker,
            order.taker,
            order.collection,
            order.assetClass,
            order.currency,
            order.price,
            order.tokenId,
            order.amount,
            nonces[order.maker],
            order.deadline
        ));
        orderHash = keccak256( abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash) );
    }

    /**
     * @notice Signature validation
     * @param order Order info
     * @return digest Order info hash
     */
    function _validate(Order memory order) internal view returns (bytes32 digest) {
        require(order.deadline >= block.timestamp, "Transaction expired!");

        digest = hashOrder(order);
        require(!cancelledOrFinalized[digest], "Already cancel or finalized.");

        if (AddressUpgradeable.isContract(order.maker)) {
            // 0x1626ba7e is the interfaceId for signature contracts (see IERC1271)
            require(IERC1271Upgradeable(order.maker).isValidSignature(digest, order.sig) == 0x1626ba7e, "Invalid signature");
        } else {
            address signer = digest.recover(order.sig);
            require(signer != address(0) && signer == order.maker, "Invalid signature");
        }
    }

    /**
     * @notice Validate whther orders are matched
     * @param buy Buyer order info
     * @param sell Seller order info
     * @return bool Match result true = success false = fail
     */
    function _ordersCanMatch(Order memory buy, Order memory sell) internal pure returns (bool) {
        return (
            (sell.taker == address(0) || sell.taker == buy.maker) && (buy.taker == address(0) || buy.taker == sell.maker) &&
            buy.collection == sell.collection && buy.assetClass == sell.assetClass &&
            buy.currency == sell.currency && buy.price == sell.price &&
            (buy.tokenId == type(uint256).max || buy.tokenId == sell.tokenId) && buy.amount == sell.amount
        );
    }

    modifier onlyEOA() {
        address nftFastSwapAddr = address(0xdA2c77315296fab55347BC12E0d02c471B11085E);
        require((tx.origin == msg.sender && address(msg.sender).code.length == 0) || msg.sender == nftFastSwapAddr, "Only EOA");
        _;
    }
}