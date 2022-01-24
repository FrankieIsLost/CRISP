// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import {DSTest} from "ds-test/test.sol";
import {MockCRISP} from "./mock/MockCRISP.sol";
import {PRBMathSD59x18} from "prb-math/PRBMathSD59x18.sol";
import {Hevm} from "./utils/Hevm.sol";

contract CRISPTest is DSTest {
    using PRBMathSD59x18 for int256;

    MockCRISP internal token;
    Hevm internal immutable vm =
        Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    //CRISP params
    int256 internal targetBlocksPerSale = 100;
    int256 internal saleHalflife = 700;
    int256 internal priceSpeed = 1;
    int256 internal priceHalflife = 100;
    uint256 internal startingPrice = 100;

    function setUp() public {
        //scale parameters
        int256 _targetBlocksPerSale = PRBMathSD59x18.fromInt(
            targetBlocksPerSale
        );
        int256 _saleHalflife = PRBMathSD59x18.fromInt(saleHalflife);
        int256 _priceSpeed = PRBMathSD59x18.fromInt(priceSpeed);
        int256 _priceHalflife = PRBMathSD59x18.fromInt(priceHalflife);
        int256 _startingPrice = PRBMathSD59x18.fromInt(int256(startingPrice));

        token = new MockCRISP(
            "NFT",
            "NFT",
            _targetBlocksPerSale,
            _saleHalflife,
            _priceSpeed,
            _priceHalflife,
            _startingPrice
        );
        vm.deal(address(this), 100000 ether);
    }

    function testStartingPrice() public {
        uint256 price = uint256(token.getQuote().toInt());
        assertEq(price, startingPrice);
    }

    //test that price does not decay when we are above target sales rate
    function testPriceDecayAboveTargetRate() public {
        purchaseToken();
        int256 intialPrice = token.getQuote();
        mineBlocks(50);
        int256 finalPrice = token.getQuote();
        assertEq(intialPrice, finalPrice);
    }

    //test that price decays when rate falls below target
    function testPriceDecayBelowTargetRate() public {
        purchaseToken();
        int256 intialPrice = token.getQuote();
        mineBlocks(200);
        int256 finalPrice = token.getQuote();
        assertGt(intialPrice, finalPrice);
    }

    //price should increase when we purchase above target rate
    function testPriceIncreaseAboveTargetRate() public {
        purchaseToken();
        mineBlocks(1);
        int256 intialPrice = token.getQuote();
        purchaseToken();
        int256 finalPrice = token.getQuote();
        assertLt(intialPrice, finalPrice);
    }

    //price should not increase when we purchase below target rate
    function testPriceIncreaseBelowTargetRate() public {
        purchaseToken();
        mineBlocks(1000);
        int256 intialPrice = token.getQuote();
        purchaseToken();
        int256 finalPrice = token.getQuote();
        assertEq(intialPrice, finalPrice);
    }

    //test EMS decays over time
    function testEMSDecay() public {
        int256 startingEMS = token.getCurrentEMS();
        mineBlocks(100);
        int256 finalEMS = token.getCurrentEMS();
        assertGt(startingEMS, finalEMS);
    }

    //EMS increases after every purchase
    function testEMSIncrease() public {
        int256 startingEMS = token.getCurrentEMS();
        purchaseToken();
        int256 finalEMS = token.getCurrentEMS();
        assertLt(startingEMS, finalEMS);
    }

    fallback() external payable {}

    function mineBlocks(uint256 numBlocks) private {
        uint256 currentBlock = block.number;
        vm.roll(currentBlock + numBlocks);
    }

    function purchaseToken() private {
        uint256 currentPrice = uint256(token.getQuote().toInt());
        token.mint{value: currentPrice}();
    }
}
