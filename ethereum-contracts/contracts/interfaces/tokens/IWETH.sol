// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.8.0;

import { ISuperToken } from "../superfluid/ISuperToken.sol";



interface IWETHCustom {
    // using native token
    function upgradeByETH() external payable;
    function upgradeByETHTo(address to) external payable;
    function downgradeToETH(uint wad) external;
}

/**
 * @title Super ETH (SETH) full interface
 * @author Superfluid
 */
// solhint-disable-next-line no-empty-blocks
interface IWETH is IWETHCustom, ISuperToken {}
