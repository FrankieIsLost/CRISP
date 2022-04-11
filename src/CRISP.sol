// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {PRBMathSD59x18} from "../lib/prb-math/contracts/PRBMathSD59x18.sol";

///@notice CRISP -- a mechanism to sell NFTs continuously at a targeted rate over time
abstract contract CRISP is ERC721 {
    using PRBMathSD59x18 for int256;

    /// ---------------------------
    /// ------- CRISP STATE -------
    /// ---------------------------

    ///@notice block on which last purchase occured
    uint64 public lastPurchaseBlock;

    ///@notice block on which we start decaying price
    uint64 public priceDecayStartBlock;

    ///@notice last minted token ID
    uint128 public curTokenId = 0;

    ///@notice Starting EMS, before time decay. 59.18-decimal fixed-point
    int256 public nextPurchaseStartingEMS;

    ///@notice Starting price for next purchase, before time decay. 59.18-decimal fixed-point
    int256 public nextPurchaseStartingPrice;

    /// ---------------------------
    /// ---- CRISP PARAMETERS -----
    /// ---------------------------

    ///@notice EMS target. 59.18-decimal fixed-point
    int256 public immutable targetEMS;

    ///@notice controls decay of sales in EMS. 59.18-decimal fixed-point
    int256 public immutable saleHalflife;

    ///@notice controls upward price movement. 59.18-decimal fixed-point
    int256 public immutable priceSpeed;

    ///@notice controls price decay. 59.18-decimal fixed-point
    int256 public immutable priceHalflife;

    /// ---------------------------
    /// ------- ERRORS  -----------
    /// ---------------------------

    error InsufficientPayment();

    error FailedToSendEther();

    constructor(
        string memory _name,
        string memory _symbol,
        int256 _targetBlocksPerSale,
        int256 _saleHalflife,
        int256 _priceSpeed,
        int256 _priceHalflife,
        int256 _startingPrice
    ) ERC721(_name, _symbol) {
        lastPurchaseBlock = blockNumber();
        priceDecayStartBlock = blockNumber();

        saleHalflife = _saleHalflife;
        priceSpeed = _priceSpeed;
        priceHalflife = _priceHalflife;

        //calculate target EMS from target blocks per sale
        targetEMS = PRBMathSD59x18.fromInt(1).div(
            PRBMathSD59x18.fromInt(1) -
                PRBMathSD59x18.fromInt(2).pow(
                    -_targetBlocksPerSale.div(saleHalflife)
                )
        );
        nextPurchaseStartingEMS = targetEMS;

        nextPurchaseStartingPrice = _startingPrice;
    }

    ///@notice get current EMS based on block number. Returns 59.18-decimal fixed-point
    function getCurrentEMS() public view returns (int256 result) {
        int256 blockInterval = int256(
            uint256(blockNumber() - lastPurchaseBlock)
        );
        blockInterval = blockInterval.fromInt();
        int256 weightOnPrev = PRBMathSD59x18.fromInt(2).pow(
            -blockInterval.div(saleHalflife)
        );
        result = nextPurchaseStartingEMS.mul(weightOnPrev);
    }

    ///@notice get quote for purchasing in current block, decaying price as needed. Returns 59.18-decimal fixed-point
    function getQuote() public view returns (int256 result) {
        if (blockNumber() <= priceDecayStartBlock) {
            result = nextPurchaseStartingPrice;
        }
        //decay price if we are past decay start block
        else {
            int256 decayInterval = int256(
                uint256(blockNumber() - priceDecayStartBlock)
            ).fromInt();
            int256 decay = (-decayInterval).div(priceHalflife).exp();
            result = nextPurchaseStartingPrice.mul(decay);
        }
    }

    ///@notice Get starting price for next purchase before time decay. Returns 59.18-decimal fixed-point
    function getNextStartingPrice(int256 lastPurchasePrice)
        public
        view
        returns (int256 result)
    {
        int256 mismatchRatio = nextPurchaseStartingEMS.div(targetEMS);
        if (mismatchRatio > PRBMathSD59x18.fromInt(1)) {
            result = lastPurchasePrice.mul(
                PRBMathSD59x18.fromInt(1) + mismatchRatio.mul(priceSpeed)
            );
        } else {
            result = lastPurchasePrice;
        }
    }

    ///@notice Find block in which time based price decay should start
    function getPriceDecayStartBlock() internal view returns (uint256 result) {
        int256 mismatchRatio = nextPurchaseStartingEMS.div(targetEMS);
        //if mismatch ratio above 1, decay should start in future
        if (mismatchRatio > PRBMathSD59x18.fromInt(1)) {
            uint256 decayInterval = uint256(
                saleHalflife.mul(mismatchRatio.log2()).ceil().toInt()
            );
            result = blockNumber() + decayInterval;
        }
        //else decay should start at the current block
        else {
            result = blockNumber();
        }
    }

    ///@notice Pay current price and mint new NFT
    function mint() public payable {
        int256 price = getQuote();
        uint256 priceScaled = uint256(price.toInt());
        if (msg.value < priceScaled) {
            revert InsufficientPayment();
        }

        unchecked {
            _mint(msg.sender, curTokenId++);
        }

        //update state
        nextPurchaseStartingEMS = getCurrentEMS() + PRBMathSD59x18.fromInt(1);
        nextPurchaseStartingPrice = getNextStartingPrice(price);
        priceDecayStartBlock = uint64(getPriceDecayStartBlock());
        lastPurchaseBlock = blockNumber();

        //hook for caller to do something with the received ETH based on the price paid
        afterMint(priceScaled);

        //issue refund
        uint256 refund = msg.value - priceScaled;
        (bool sent, ) = msg.sender.call{value: refund}("");
        if (!sent) {
            revert FailedToSendEther();
        }
    }

    function afterMint(uint256 priceScaled) internal virtual {}

    function blockNumber() internal view returns (uint64) {
        return uint64(block.number);
    }
}
