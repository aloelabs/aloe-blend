// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./FullMath.sol";

struct UINT512 {
    // Least significant bits
    uint256 LS;
    // Most significant bits
    uint256 MS;
}

library UINT512Math {
    /// @dev Adds an (LS, MS) pair in place. Assumes result fits in uint512
    function iadd(
        UINT512 storage self,
        uint256 LS,
        uint256 MS
    ) internal {
        unchecked {
            if (self.LS > type(uint256).max - LS) {
                self.LS = addmod(self.LS, LS, type(uint256).max);
                self.MS += 1 + MS;
            } else {
                self.LS += LS;
                self.MS += MS;
            }
        }
    }

    /// @dev Adds an (LS, MS) pair to self. Assumes result fits in uint512
    function add(
        UINT512 memory self,
        uint256 LS,
        uint256 MS
    ) internal pure returns (uint256, uint256) {
        unchecked {
            return
                (self.LS > type(uint256).max - LS)
                    ? (addmod(self.LS, LS, type(uint256).max), self.MS + MS + 1)
                    : (self.LS + LS, self.MS + MS);
        }
    }

    /// @dev Subtracts an (LS, MS) pair in place. Assumes result > 0
    function isub(
        UINT512 storage self,
        uint256 LS,
        uint256 MS
    ) internal {
        unchecked {
            if (self.LS < LS) {
                self.LS = type(uint256).max + self.LS - LS;
                self.MS -= 1 + MS;
            } else {
                self.LS -= LS;
                self.MS -= MS;
            }
        }
    }

    /// @dev Subtracts an (LS, MS) pair from self. Assumes result > 0
    function sub(
        UINT512 memory self,
        uint256 LS,
        uint256 MS
    ) internal pure returns (uint256, uint256) {
        unchecked {
            return (self.LS < LS) ? (type(uint256).max + self.LS - LS, self.MS - MS - 1) : (self.LS - LS, self.MS - MS);
        }
    }

    /// @dev Multiplies self by single uint256, s. Assumes result fits in uint512
    function muls(UINT512 memory self, uint256 s) internal pure returns (uint256, uint256) {
        unchecked {
            self.MS *= s;
            (self.LS, s) = FullMath.mul512(self.LS, s);
            return (self.LS, self.MS + s);
        }
    }
}
