// SPDX-License-Identifier: UNLICENSED

interface IMultiSigWallet {
    function submitTransaction(address destination, uint value, bytes calldata data)
        external
        returns (uint transactionId);
}
