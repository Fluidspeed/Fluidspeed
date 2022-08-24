// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;


interface IResolver {

    event Set(string indexed name, address target);

    /**
     * @dev Set resolver address name
     */
    function set(string calldata name, address target) external;

    /**
     * @dev Get address by name
     */
    function get(string calldata name) external view returns (address);

}
