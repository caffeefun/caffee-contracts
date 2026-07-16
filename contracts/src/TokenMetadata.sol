// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*
 * TokenMetadata — fully on-chain image / description / socials for Caffee
 * fair-launch tokens on Robinhood Chain.
 *
 * Design: an ADDITIVE side-car registry. It does NOT replace or modify the
 * deployed CaffeeLaunch factory, so it introduces no registry fragmentation and
 * lets ALREADY-launched tokens (e.g. CTEST) be described too. Everything lives
 * on-chain: `data` is a UTF-8 JSON blob carrying the (compressed, client-side)
 * image as a data: URI plus text fields, e.g.
 *   {"image":"data:image/webp;base64,…","description":"…",
 *    "website":"…","twitter":"…","telegram":"…"}
 * There is no backend, no IPFS, no off-chain storage of any kind.
 *
 * Authorization: only a token's original creator may set/update its metadata.
 * The creator is read from the token's bonding curve (CaffeeCurve.creator()),
 * looked up via CaffeeLaunch.curveOf(token).
 */

interface ICaffeeLaunch {
    function curveOf(address token) external view returns (address curve);
}

interface ICaffeeCurve {
    function creator() external view returns (address);
}

contract TokenMetadata {
    /// The deployed CaffeeLaunch factory this registry authorizes against.
    ICaffeeLaunch public immutable launchpad;

    /// Hard cap on the stored blob. The client compresses logos to well under
    /// this (≈128–256px webp); the cap only guards against storage griefing.
    uint256 public constant MAX_BYTES = 32768; // 32 KB

    /// token => on-chain JSON metadata blob.
    mapping(address => string) public metadata;

    event MetadataSet(address indexed token, address indexed creator, string data);

    constructor(address _launchpad) {
        require(_launchpad != address(0), "LAUNCHPAD_ZERO");
        launchpad = ICaffeeLaunch(_launchpad);
    }

    /// Set or update `token`'s metadata. Caller MUST be the token's creator.
    function set(address token, string calldata data) external {
        require(bytes(data).length <= MAX_BYTES, "TOO_BIG");
        address curve = launchpad.curveOf(token);
        require(curve != address(0), "NOT_LAUNCHED");
        require(msg.sender == ICaffeeCurve(curve).creator(), "NOT_CREATOR");
        metadata[token] = data;
        emit MetadataSet(token, msg.sender, data);
    }

    /// Batch read for directory/grid views: one call for many tokens
    /// (empty string for tokens without metadata).
    function getMany(address[] calldata tokens) external view returns (string[] memory out) {
        out = new string[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            out[i] = metadata[tokens[i]];
        }
    }
}
