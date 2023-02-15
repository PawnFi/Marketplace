// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface CreateProxyFactory {
    
    function deploy(address logic, address admin, bytes memory data, bytes32 salt) external returns(address proxy);

    function computeAddress(bytes32 salt) external view returns (address);
}
