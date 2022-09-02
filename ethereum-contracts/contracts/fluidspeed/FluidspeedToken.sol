// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.16;

import { IFluidspeed } from "../interfaces/fluidspeed/IFluidspeed.sol";
import { ISuperAgreement } from "../interfaces/fluidspeed/ISuperAgreement.sol";
import { IFluidspeedGovernance } from "../interfaces/fluidspeed/IFluidspeedGovernance.sol";
import { IFluidspeedToken, FluidspeedErrors } from "../interfaces/fluidspeed/IFluidspeedToken.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { EventsEmitter } from "../libs/EventsEmitter.sol";
import { FixedSizeData } from "../libs/FixedSizeData.sol";

/**
 * @title Fluidspeed's token implementation
 *
 * @author Fluidspeed
 */
abstract contract FluidspeedToken is IFluidspeedToken
{

    bytes32 private constant _REWARD_ADDRESS_CONFIG_KEY =
        keccak256("org.fluidspeed-finance.fluidspeed.rewardAddress");

    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Fluidspeed contract
    IFluidspeed immutable internal _host;

    /// @dev Active agreement bitmap
    mapping(address => uint256) internal _inactiveAgreementBitmap;

    /// @dev Shared Settled balance for the account
    mapping(address => int256) internal _sharedSettledBalances;

    /// @dev Total supply
    uint256 internal _totalSupply;

    // NOTE: for future compatibility, these are reserved solidity slots
    // The sub-class of FluidspeedToken solidity slot will start after _reserve13
    uint256 internal _reserve4;
    uint256 private _reserve5;
    uint256 private _reserve6;
    uint256 private _reserve7;
    uint256 private _reserve8;
    uint256 private _reserve9;
    uint256 private _reserve10;
    uint256 private _reserve11;
    uint256 private _reserve12;
    uint256 internal _reserve13;

    constructor(
        IFluidspeed host
    ) {
        _host = host;
    }
	
	
	/**************************************************************************
    * Modifiers
    *************************************************************************/

    modifier onlyAgreement() {
        if (!_host.isAgreementClassListed(ISuperAgreement(msg.sender))) {
            revert FluidspeedErrors.ONLY_LISTED_AGREEMENT(FluidspeedErrors.SF_TOKEN_ONLY_LISTED_AGREEMENT);
        }
        _;
    }

    modifier onlyHost() {
        if (address(_host) != msg.sender) {
            revert FluidspeedErrors.ONLY_HOST(FluidspeedErrors.SF_TOKEN_ONLY_HOST);
        }
        _;
    }

    /// @dev IFluidspeedToken.getHost implementation
    function getHost()
       external view
       override(IFluidspeedToken)
       returns(address host)
    {
       return address(_host);
    }

    /**************************************************************************
     * Real-time balance functions
     *************************************************************************/

    /// @dev IFluidspeedToken.realtimeBalanceOf implementation
    function realtimeBalanceOf(
       address account,
       uint256 timestamp
    )
       public view override
       returns (
           int256 availableBalance,
           uint256 deposit,
           uint256 owedDeposit)
    {
        availableBalance = _sharedSettledBalances[account];
        ISuperAgreement[] memory activeAgreements = getAccountActiveAgreements(account);
        for (uint256 i = 0; i < activeAgreements.length; ++i) {
            (
                int256 agreementDynamicBalance,
                uint256 agreementDeposit,
                uint256 agreementOwedDeposit) = activeAgreements[i]
                    .realtimeBalanceOf(
                         this,
                         account,
                         timestamp
                     );
            deposit = deposit + agreementDeposit;
            owedDeposit = owedDeposit + agreementOwedDeposit;
            // 1. Available Balance = Dynamic Balance - Max(0, Deposit - OwedDeposit)
            // 2. Deposit should not be shared between agreements
            availableBalance = availableBalance
                + agreementDynamicBalance
                - (
                    agreementDeposit > agreementOwedDeposit ?
                    (agreementDeposit - agreementOwedDeposit) : 0
                ).toInt256();
        }
    }

    /// @dev IFluidspeedToken.realtimeBalanceOfNow implementation
    function realtimeBalanceOfNow(
       address account
    )
        public view override
        returns (
            int256 availableBalance,
            uint256 deposit,
            uint256 owedDeposit,
            uint256 timestamp)
    {
        timestamp = _host.getNow();
        (
            availableBalance,
            deposit,
            owedDeposit
        ) = realtimeBalanceOf(account, timestamp);
    }

    function isAccountCritical(
        address account,
        uint256 timestamp
    )
        public view override
        returns(bool isCritical)
    {
        (int256 availableBalance,,) = realtimeBalanceOf(account, timestamp);
        return availableBalance < 0;
    }

    function isAccountCriticalNow(
       address account
    )
        external view override
       returns(bool isCritical)
    {
        return isAccountCritical(account, _host.getNow());
    }

    function isAccountSolvent(
        address account,
        uint256 timestamp
    )
        public view override
        returns(bool isSolvent)
    {
        (int256 availableBalance, uint256 deposit, uint256 owedDeposit) =
            realtimeBalanceOf(account, timestamp);
        // Available Balance = Realtime Balance - Max(0, Deposit - OwedDeposit)
        int realtimeBalance = availableBalance
            + (deposit > owedDeposit ? (deposit - owedDeposit) : 0).toInt256();
        return realtimeBalance >= 0;
    }

    function isAccountSolventNow(
       address account
    )
       external view override
       returns(bool isSolvent)
    {
        return isAccountSolvent(account, _host.getNow());
    }

    /// @dev IFluidspeedToken.getAccountActiveAgreements implementation
    function getAccountActiveAgreements(address account)
       public view override
       returns(ISuperAgreement[] memory)
    {
       return _host.mapAgreementClasses(~_inactiveAgreementBitmap[account]);
    }

    /**************************************************************************
     * Token implementation helpers
     *************************************************************************/

    function _mint(
        address account,
        uint256 amount
    )
        internal
    {
        _sharedSettledBalances[account] = _sharedSettledBalances[account] + amount.toInt256();
        _totalSupply = _totalSupply + amount;
    }

    function _burn(
        address account,
        uint256 amount
    )
        internal
    {
        (int256 availableBalance,,) = realtimeBalanceOf(account, _host.getNow());
        if (availableBalance < amount.toInt256()) {
            revert FluidspeedErrors.INSUFFICIENT_BALANCE(FluidspeedErrors.SF_TOKEN_BURN_INSUFFICIENT_BALANCE);
        }
        _sharedSettledBalances[account] = _sharedSettledBalances[account] - amount.toInt256();
        _totalSupply = _totalSupply - amount;
    }

    function _move(
        address from,
        address to,
        int256 amount
    )
        internal
    {
        (int256 availableBalance,,) = realtimeBalanceOf(from, _host.getNow());
        if (availableBalance < amount) {
            revert FluidspeedErrors.INSUFFICIENT_BALANCE(FluidspeedErrors.SF_TOKEN_MOVE_INSUFFICIENT_BALANCE);
        }
        _sharedSettledBalances[from] = _sharedSettledBalances[from] - amount;
        _sharedSettledBalances[to] = _sharedSettledBalances[to] + amount;
    }

    function _getRewardAccount() internal view returns (address rewardAccount) {
        IFluidspeedGovernance gov = _host.getGovernance();
        rewardAccount = gov.getConfigAsAddress(_host, this, _REWARD_ADDRESS_CONFIG_KEY);
    }
	
/**************************************************************************
     * Super Agreement hosting functions
     *************************************************************************/

    /// @dev IFluidspeedToken.createAgreement implementation
    function createAgreement(
        bytes32 id,
        bytes32[] calldata data
    )
        external override
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(abi.encode("AgreementData", agreementClass, id));
        if (FixedSizeData.hasData(slot, data.length)) {
            revert FluidspeedErrors.ALREADY_EXISTS(FluidspeedErrors.SF_TOKEN_AGREEMENT_ALREADY_EXISTS);
        }
        FixedSizeData.storeData(slot, data);
        emit AgreementCreated(agreementClass, id, data);
    }

    /// @dev IFluidspeedToken.getAgreementData implementation
    function getAgreementData(
        address agreementClass,
        bytes32 id,
        uint dataLength
    )
        external view override
        returns(bytes32[] memory data)
    {
        bytes32 slot = keccak256(abi.encode("AgreementData", agreementClass, id));
        data = FixedSizeData.loadData(slot, dataLength);
    }
/// @dev IFluidspeedToken.updateAgreementData implementation
    function updateAgreementData(
        bytes32 id,
        bytes32[] calldata data
    )
        external override
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(abi.encode("AgreementData", agreementClass, id));
        FixedSizeData.storeData(slot, data);
        emit AgreementUpdated(msg.sender, id, data);
    }

    /// @dev IFluidspeedToken.terminateAgreement implementation
    function terminateAgreement(
        bytes32 id,
        uint dataLength
    )
        external override
    {
        address agreementClass = msg.sender;
        bytes32 slot = keccak256(abi.encode("AgreementData", agreementClass, id));
        if (!FixedSizeData.hasData(slot,dataLength)) {
            revert FluidspeedErrors.DOES_NOT_EXIST(FluidspeedErrors.SF_TOKEN_AGREEMENT_DOES_NOT_EXIST);
        }
        FixedSizeData.eraseData(slot, dataLength);
        emit AgreementTerminated(msg.sender, id);
    }
    /// @dev IFluidspeedToken.updateAgreementState implementation
    function updateAgreementStateSlot(
        address account,
        uint256 slotId,
        bytes32[] calldata slotData
    )
        external override
    {
        bytes32 slot = keccak256(abi.encode("AgreementState", msg.sender, account, slotId));
        FixedSizeData.storeData(slot, slotData);
        emit AgreementStateUpdated(msg.sender, account, slotId);
    }
/// @dev IFluidspeedToken.getAgreementState implementation
    function getAgreementStateSlot(
        address agreementClass,
        address account,
        uint256 slotId,
        uint dataLength
    )
        external override view
        returns (bytes32[] memory slotData) {
        bytes32 slot = keccak256(abi.encode("AgreementState", agreementClass, account, slotId));
        slotData = FixedSizeData.loadData(slot, dataLength);
    }

    /// @dev IFluidspeedToken.settleBalance implementation
    function settleBalance(
        address account,
        int256 delta
    )
        external override
        onlyAgreement
    {
        _sharedSettledBalances[account] = _sharedSettledBalances[account] + delta;
    }

}
