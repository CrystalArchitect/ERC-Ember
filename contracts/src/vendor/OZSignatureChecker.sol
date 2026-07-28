// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev Pinned, locally vendored subset of OpenZeppelin Contracts v5.0.2
/// SignatureChecker/ECDSA behavior. Supports EOAs and ERC-1271 accounts.
library OZSignatureChecker {
    bytes4 private constant _ERC1271_MAGICVALUE = 0x1626ba7e;
    uint256 private constant _SECP256K1N_DIV_2 = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
        if (signer.code.length == 0) return recover(hash, signature) == signer;
        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeWithSelector(_ERC1271_MAGICVALUE, hash, signature));
        return success && result.length >= 32 && bytes4(result) == _ERC1271_MAGICVALUE;
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        if (signature.length == 65) {
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
        } else if (signature.length == 64) {
            bytes32 vs;
            assembly {
                r := mload(add(signature, 0x20))
                vs := mload(add(signature, 0x40))
            }
            s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            v = uint8((uint256(vs) >> 255) + 27);
        } else {
            return address(0);
        }
        if (uint256(s) > _SECP256K1N_DIV_2 || (v != 27 && v != 28)) return address(0);
        return ecrecover(hash, v, r, s);
    }
}
