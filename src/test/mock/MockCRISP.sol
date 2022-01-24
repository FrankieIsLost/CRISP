// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import {CRISP} from "../../CRISP.sol";

contract MockCRISP is CRISP {
    constructor(
        string memory _name,
        string memory _symbol,
        int256 _targetBlocksPerSale,
        int256 _saleHalflife,
        int256 _priceSpeed,
        int256 _priceHalflife,
        int256 _startingPrice
    )
        CRISP(
            _name,
            _symbol,
            _targetBlocksPerSale,
            _saleHalflife,
            _priceSpeed,
            _priceHalflife,
            _startingPrice
        )
    {}

    function tokenURI(uint256)
        public
        pure
        virtual
        override
        returns (string memory)
    {}
}
