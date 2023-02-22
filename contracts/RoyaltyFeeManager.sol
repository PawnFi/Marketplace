// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/interfaces/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IRoyaltyFeeManager.sol";
import "./interfaces/IOwnable.sol";

/**
 * @title Pawnfi's RoyaltyFeeManager Contract
 * @author Pawnfi
 */
contract RoyaltyFeeManager is OwnableUpgradeable, IRoyaltyFeeManager {

    // Denominator, used for calculating percentage
    uint256 private constant DENOMINATOR = 10000;

    // ERC721 interfaceID
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    // ERC1155 interfaceID
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    // ERC2981 interfaceID
    bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    /**
     * @notice Royalty fee info
     * @member setter Fee setter
     * @member receiver Fee receiver
     * @member fee Fee percentage
     */
    struct FeeInfo {
        address setter;
        address receiver;
        uint256 fee;
    }

    /// @notice Royalty fee rate limit (if enforced for fee royalty in percentage (10,000 = 100%)
    uint256 public royaltyFeeLimit;

    // Store information related to royalty fees for different NFTs
    mapping(address => FeeInfo) private _royaltyFeeInfoCollection;

    /// @notice Standard rayalty fee rate
    uint256 public standardRoyaltyFee;

    /// @notice The identifier for enabling the general standard royalty fee rate
    bool public globallyEnabled;

    /// @notice Emitted when update Standard rayalty fee rate
    event NewStandardRoyaltyFee(uint256 standardRoyaltyFee);

    /// @notice Emitted when enable the general standard royalty fee rate
    event GloballyEnabledUpdate(bool globallyEnabled);

    /// @notice Trigger when owner set new standard rayalty fee rate
    event NewRoyaltyFeeLimit(uint256 royaltyFeeLimit);
    
    /// @notice Trigger when  set new  royalty fee info
    event RoyaltyFeeUpdate(address indexed collection, address indexed setter, address indexed receiver, uint256 fee);

    /**
     * @notice Initialize contract parameters - only execute once
     * @param owner_ Owner address
     * @param royaltyFeeLimit_ Royalty limit
     */
    function initialize(address owner_, uint256 royaltyFeeLimit_) external initializer {
        _transferOwnership(owner_);
        require(royaltyFeeLimit_ <= 9500, "Royalty fee limit too high");
        royaltyFeeLimit = royaltyFeeLimit_;
    }

    /**
     * @notice Set new standard rayalty fee rate - exclusive to owner
     * @param newStandardRoyaltyFee Standard rayalty fee rate
     */
    function setStandardRoyaltyFee(uint256 newStandardRoyaltyFee) external onlyOwner {
        require(newStandardRoyaltyFee <= royaltyFeeLimit, "Royalty fee too high");
        standardRoyaltyFee = newStandardRoyaltyFee;
        emit NewStandardRoyaltyFee(newStandardRoyaltyFee);
    }

    /**
     * @notice Set globally enabling the standard rayalty fee rate - exclusive to owner
     * @param newGloballyEnabled Global identifier
     */
    function setGloballyEnabled(bool newGloballyEnabled) external onlyOwner {
        globallyEnabled = newGloballyEnabled;
        emit GloballyEnabledUpdate(newGloballyEnabled);
    }

    /**
     * @notice Update royalty info for collection
     * @param newRoyaltyFeeLimit new royalty fee limit (500 = 5%, 1,000 = 10%)
     */
    function updateRoyaltyFeeLimit(uint256 newRoyaltyFeeLimit) external onlyOwner {
        require(newRoyaltyFeeLimit <= 9500, "Royalty fee limit too high");
        royaltyFeeLimit = newRoyaltyFeeLimit;

        emit NewRoyaltyFeeLimit(newRoyaltyFeeLimit);
    }

    /**
     * @notice Calculate royalty info for a collection address and a sale gross amount
     * @param collection collection address
     * @param amount amount
     * @return receiver address and amount received by royalty recipient
     */
    function royaltyInfo(address collection, uint256 amount) public view returns (address, uint256) {
        return (_royaltyFeeInfoCollection[collection].receiver, (amount * _royaltyFeeInfoCollection[collection].fee) / DENOMINATOR);
    }

    /**
     * @notice View royalty info for a collection address
     * @param collection collection address
     * @return address Fee setter address
     * @return address Fee receiver address
     * @return uint256 Fee rate
     */
    function royaltyFeeInfoCollection(address collection) public view returns (address, address, uint256) {
        return (_royaltyFeeInfoCollection[collection].setter, _royaltyFeeInfoCollection[collection].receiver, _royaltyFeeInfoCollection[collection].fee);
    }

    /**
     * @notice Calculate royalty fee and get recipient
     * @param collection address of the NFT contract
     * @param tokenId tokenId
     * @param amount amount to transfer
     * @return receiver Fee receiver
     * @return royaltyAmount Royalty fee amount
     */
    function calculateRoyaltyFeeAndGetRecipient(address collection, uint256 tokenId, uint256 amount) external view override returns (address receiver, uint256 royaltyAmount) {
        // 1. Check if there is a royalty info in the system
        (receiver, royaltyAmount) = royaltyInfo(collection, amount);

        // 2. If the receiver is address(0), check if it supports the ERC2981 interface
        if (receiver == address(0)) {
            if (IERC2981Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC2981)) {
                (bool status, bytes memory data) = collection.staticcall(
                    abi.encodeWithSelector(IERC2981Upgradeable.royaltyInfo.selector, tokenId, amount)
                );
                if (status) {
                    (receiver, royaltyAmount) = abi.decode(data, (address, uint256));
                }
            }
        }
        if (receiver == address(0)) {
            royaltyAmount = 0;
        }else{
            if(globallyEnabled) {
                royaltyAmount = amount * standardRoyaltyFee / DENOMINATOR;
            } else {
                uint256 referenceRoyaltyAmount = amount * royaltyFeeLimit / DENOMINATOR;
                if(royaltyAmount > referenceRoyaltyAmount) {
                    royaltyAmount = referenceRoyaltyAmount;
                }
            }
        }
    }

    /**
     * @notice Update royalty info for collection
     * @param collection address of the NFT contract
     * @param setter address that sets the receiver
     * @param receiver receiver for the royalty fee
     * @param fee fee (500 = 5%, 1,000 = 10%)
     */
    function updateRoyaltyInfoForCollection(address collection, address setter, address receiver, uint256 fee) external onlyOwner {
        _updateRoyaltyInfoForCollection(collection, setter, receiver, fee);
    }

    /**
     * @notice Update royalty info for collection if admin
     * @dev Only to be called if there is no setter address
     * @param collection address of the NFT contract
     * @param setter address that sets the receiver
     * @param receiver receiver for the royalty fee
     * @param fee fee (500 = 5%, 1,000 = 10%)
     */
    function updateRoyaltyInfoForCollectionIfAdmin(address collection, address setter, address receiver, uint256 fee) external {
        require(!IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC2981), "Admin: Must not be ERC2981");
        require(msg.sender == IOwnable(collection).admin(), "Admin: Not the admin");

        _updateRoyaltyInfoForCollectionIfOwnerOrAdmin(collection, setter, receiver, fee);
    }

    /**
     * @notice Update royalty info for collection if owner
     * @dev Only to be called if there is no setter address
     * @param collection address of the NFT contract
     * @param setter address that sets the receiver
     * @param receiver receiver for the royalty fee
     * @param fee fee (500 = 5%, 1,000 = 10%)
     */
    function updateRoyaltyInfoForCollectionIfOwner(address collection, address setter, address receiver, uint256 fee) external {
        require(!IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC2981), "Owner: Must not be ERC2981");
        require(msg.sender == IOwnable(collection).owner(), "Owner: Not the owner");

        _updateRoyaltyInfoForCollectionIfOwnerOrAdmin(collection, setter, receiver, fee);
    }

    /**
     * @notice Update royalty info for collection
     * @dev Only to be called if there msg.sender is the setter
     * @param collection address of the NFT contract
     * @param setter address that sets the receiver
     * @param receiver receiver for the royalty fee
     * @param fee fee (500 = 5%, 1,000 = 10%)
     */
    function updateRoyaltyInfoForCollectionIfSetter(address collection, address setter, address receiver, uint256 fee) external {
        (address currentSetter, , ) = royaltyFeeInfoCollection(collection);
        require(msg.sender == currentSetter, "Setter: Not the setter");

        _updateRoyaltyInfoForCollection(collection, setter, receiver, fee);
    }

    /**
     * @notice Check royalty info for collection
     * @param collection collection address
     * @return (whether there is a setter (address(0 if not)),
     * Position
     * 0: Royalty setter is set in the registry
     * 1: ERC2981 and no setter
     * 2: setter can be set using owner()
     * 3: setter can be set using admin()
     * 4: setter cannot be set, nor support for ERC2981
     */
    function checkForCollectionSetter(address collection) external view returns (address, uint8) {
        (address currentSetter, , ) = royaltyFeeInfoCollection(collection);

        if (currentSetter != address(0)) {
            return (currentSetter, 0);
        }

        try IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC2981) returns (bool interfaceSupport) {
            if (interfaceSupport) {
                return (address(0), 1);
            }
        } catch {}

        try IOwnable(collection).owner() returns (address setter) {
            return (setter, 2);
        } catch {
            try IOwnable(collection).admin() returns (address setter) {
                return (setter, 3);
            } catch {
                return (address(0), 4);
            }
        }
    }

    /**
     * @notice Update information and perform checks before updating royalty fee registry
     * @param collection address of the NFT contract
     * @param setter address that sets the receiver
     * @param receiver receiver for the royalty fee
     * @param fee fee (500 = 5%, 1,000 = 10%)
     */
    function _updateRoyaltyInfoForCollectionIfOwnerOrAdmin(address collection, address setter, address receiver, uint256 fee) internal {
        (address currentSetter, , ) = royaltyFeeInfoCollection(collection);
        require(currentSetter == address(0), "Setter: Already set");

        require(
            (IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC721) ||
                IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC1155)),
            "Setter: Not ERC721/ERC1155"
        );

        _updateRoyaltyInfoForCollection(collection, setter, receiver, fee);
    }

    /**
     * @notice Update royalty fee info for NFT
     * @param collection address of the NFT contract
     * @param setter Royalty fee rate setter
     * @param receiver Royalty fee receiver
     * @param fee Royalty fee rate
     */
    function _updateRoyaltyInfoForCollection(address collection, address setter, address receiver, uint256 fee) private  {
        require(fee <= royaltyFeeLimit, "Royalty fee too high");
        _royaltyFeeInfoCollection[collection] = FeeInfo({setter: setter, receiver: receiver, fee: fee});

        emit RoyaltyFeeUpdate(collection, setter, receiver, fee);
    }
}