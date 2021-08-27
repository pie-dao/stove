//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.1;

interface IRecipe {
    function bake(
        address _tokenInput,
        address _tokenOutput,
        uint256 _maxInput,
        bytes memory _data
    ) external returns (uint256 _usedInput, uint256 _bakedOutput);
}
