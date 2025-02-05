use crate::address::{AztecAddress, EthAddress};
use crate::mocked::VerificationKey;
use crate::abis::function_selector::FunctionSelector;
use crate::abis::contract_class_function_leaf_preimage::ContractClassFunctionLeafPreimage;
use crate::contract_class_id::ContractClassId;
use crate::abis::side_effect::{SideEffect};
use crate::utils::uint256::U256;
use crate::constants::{
    ARGS_HASH_CHUNK_COUNT, ARGS_HASH_CHUNK_LENGTH, FUNCTION_TREE_HEIGHT, NUM_FIELDS_PER_SHA256,
    GENERATOR_INDEX__SILOED_NOTE_HASH, GENERATOR_INDEX__OUTER_NULLIFIER, GENERATOR_INDEX__VK,
    GENERATOR_INDEX__CONSTRUCTOR, GENERATOR_INDEX__PARTIAL_ADDRESS, GENERATOR_INDEX__CONTRACT_ADDRESS,
    GENERATOR_INDEX__NOTE_HASH_NONCE, GENERATOR_INDEX__UNIQUE_NOTE_HASH, GENERATOR_INDEX__FUNCTION_ARGS
};
use crate::messaging::l2_to_l1_message::L2ToL1Message;
use crate::merkle_tree::root::root_from_sibling_path;

use dep::std::hash::{pedersen_hash_with_separator, sha256};

pub fn sha256_to_field<N>(bytes_to_hash: [u8; N]) -> Field {
    let sha256_hashed = sha256(bytes_to_hash);

    // Convert it to a field element
    let mut v = 1;
    let mut high = 0 as Field;
    let mut low = 0 as Field;

    for i in 0..16 {
        high = high + (sha256_hashed[15 - i] as Field) * v;
        low = low + (sha256_hashed[16 + 15 - i] as Field) * v;
        v = v * 256;
    }

    // Abuse that a % p + b % p = (a + b) % p and that low < p
    let hash_in_a_field = low + high * v;

    hash_in_a_field
}

pub fn hash_args<N>(args: [Field; N]) -> Field {
    if args.len() == 0 {
        0
    } else {
        let mut chunks_hashes = [0; ARGS_HASH_CHUNK_COUNT];
        for i in 0..ARGS_HASH_CHUNK_COUNT {
            let mut chunk_hash = 0;
            let start_chunk_index = i * ARGS_HASH_CHUNK_LENGTH;
            if start_chunk_index < args.len() {
                let mut chunk_args = [0; ARGS_HASH_CHUNK_LENGTH];
                for j in 0..ARGS_HASH_CHUNK_LENGTH {
                    let item_index = i * ARGS_HASH_CHUNK_LENGTH + j;
                    if item_index < args.len() {
                        chunk_args[j] = args[item_index];
                    }
                }
                chunk_hash = pedersen_hash(chunk_args, GENERATOR_INDEX__FUNCTION_ARGS);
            }
            chunks_hashes[i] = chunk_hash;
        }
        pedersen_hash(chunks_hashes, GENERATOR_INDEX__FUNCTION_ARGS)
    }
}

pub fn private_functions_root_from_siblings(
    selector: FunctionSelector,
    vk_hash: Field,
    function_leaf_index: Field,
    function_leaf_sibling_path: [Field; FUNCTION_TREE_HEIGHT]
) -> Field {
    let function_leaf_preimage = ContractClassFunctionLeafPreimage { selector, vk_hash };
    let function_leaf = function_leaf_preimage.hash();
    root_from_sibling_path(function_leaf, function_leaf_index, function_leaf_sibling_path)
}

pub fn silo_note_hash(address: AztecAddress, inner_commitment: Field) -> Field {
    pedersen_hash(
        [
        address.to_field(),
        inner_commitment
    ],
        GENERATOR_INDEX__SILOED_NOTE_HASH
    )
}

pub fn silo_nullifier(address: AztecAddress, nullifier: Field) -> Field {
    pedersen_hash(
        [
        address.to_field(),
        nullifier
    ],
        GENERATOR_INDEX__OUTER_NULLIFIER
    )
}

pub fn merkle_hash(left: Field, right: Field) -> Field {
    pedersen_hash([left, right], 0)
}

pub fn stdlib_recursion_verification_key_compress_native_vk(_vk: VerificationKey) -> Field {
    // Original cpp code
    // stdlib::recursion::verification_key<CT::bn254>::compress_native(private_call.vk, GeneratorIndex::VK);
    // The above cpp method is only ever called on verification key, so it has been special cased here
    let _hash_index = GENERATOR_INDEX__VK;
    0
}

pub fn compute_l2_to_l1_hash(
    contract_address: AztecAddress,
    rollup_version_id: Field,
    chain_id: Field,
    message: L2ToL1Message
) -> Field {
    let mut bytes: BoundedVec<u8, 160> = BoundedVec::new();

    let inputs = [
        contract_address.to_field(), rollup_version_id, message.recipient.to_field(), chain_id, message.content
    ];
    for i in 0..inputs.len() {
        // TODO are bytes be in fr.to_buffer() ?
        let item_bytes = inputs[i].to_be_bytes(32);
        for j in 0..32 {
            bytes.push(item_bytes[j]);
        }
    }

    sha256_to_field(bytes.storage)
}

// Computes sha256 hash of 2 input hashes stored in 4 fields.
// 
// This method is bn254 specific. Two fields is needed in order to 
// encode the sha256 output. It can be abstracted away with any 4-2 hash function.
//
// TODO(Jan and David): This is used for the encrypted_log hashes.
// Can we check to see if we can just use hash_to_field or pedersen_compress here?
//
// Returning a Field would be desirable because then this can be replaced with 
// poseidon without changing the rest of the code
//
pub fn accumulate_sha256(input: [U128; 4]) -> [Field; NUM_FIELDS_PER_SHA256] {
    // This is a note about the cpp code, since it takes an array of Fields
    // instead of a U128.
    // 4 Field elements when converted to bytes will usually 
    // occupy 4 * 32 = 128 bytes.
    // However, this function is making the assumption that each Field 
    // only occupies 128 bits.
    //
    // TODO(David): This does not seem to be getting guaranteed anywhere in the code?
    //
    // Concatenate 4 u128 bit integers into a byte array.
    let mut hash_input_flattened = [0; 64];
    for offset in 0..4 {
        let input_as_bytes = input[offset].to_be_bytes();
        for byte_index in 0..16 {
            hash_input_flattened[offset * 16 + byte_index] = input_as_bytes[byte_index];
        }
    }

    let sha_digest = dep::std::hash::sha256(hash_input_flattened);

    U256::from_bytes32(sha_digest).to_u128_limbs()
}

pub fn compute_logs_hash(
    previous_log_hash: [Field; 2],
    current_log_hash: [Field; 2]
) -> [Field; NUM_FIELDS_PER_SHA256] {
    accumulate_sha256(
        [
        U128::from_integer(previous_log_hash[0]),
        U128::from_integer(previous_log_hash[1]),
        U128::from_integer(current_log_hash[0]),
        U128::from_integer(current_log_hash[1])
    ]
    )
}

pub fn compute_note_hash_nonce(first_nullifier: Field, commitment_index: u64) -> Field {
    pedersen_hash(
        [
        first_nullifier,
        commitment_index as Field
    ],
        GENERATOR_INDEX__NOTE_HASH_NONCE
    )
}

pub fn compute_unique_siloed_note_hash(nonce: Field, siloed_note_hash: Field) -> Field {
    pedersen_hash(
        [
        nonce,
        siloed_note_hash
    ],
        GENERATOR_INDEX__UNIQUE_NOTE_HASH
    )
}

pub fn compute_unique_siloed_note_hashes<N>(
    first_nullifier: Field,
    siloed_note_hashes: [SideEffect; N]
) -> [SideEffect; N] {
    let mut unique_siloed_note_hashes = [SideEffect::empty(); N];
    for i in 0..N {
        let siloed_note_hash = siloed_note_hashes[i];
        if siloed_note_hash.value != 0 {
            let nonce = compute_note_hash_nonce(first_nullifier, i);
            unique_siloed_note_hashes[i] = SideEffect {
                value: compute_unique_siloed_note_hash(nonce, siloed_note_hash.value),
                counter: siloed_note_hash.counter
                };
        }
    }
    unique_siloed_note_hashes
}

pub fn pedersen_hash<N>(inputs: [Field; N], hash_index: u32) -> Field {
    dep::std::hash::pedersen_hash_with_separator(inputs, hash_index)
}

#[test]
fn smoke_sha256_to_field() {
    let full_buffer = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
        40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
        80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99,
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
        120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139,
        140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159
    ];
    let result = sha256_to_field(full_buffer);
    assert(result == 0x142a6d57007171f6eaa33d55976d9dbe739c889c8e920f115f7808dea184c718);
}

#[test]
fn compute_var_args_hash() {
    let mut input = [0; 800];
    for i in 0..800 {
        input[i] = i as Field;
    }
    let hash = hash_args(input);
    assert(hash == 0x371960dd84ed3445ab099ac4c1af5ba90e0c713b593e0ca52ee532087c7f097);
}

#[test]
fn compute_l2_l1_hash() {
    // All zeroes
    let hash_result = compute_l2_to_l1_hash(AztecAddress::from_field(0), 0, 0, L2ToL1Message::empty());
    assert(hash_result == 0x2266ac2f9f0c19c015239ef5ea85862fc6fac00db73779b220a4d49c4856c2e1);

    // Non-zero case
    let message = L2ToL1Message { recipient: EthAddress::from_field(3), content: 5 };
    let hash_result = compute_l2_to_l1_hash(AztecAddress::from_field(1), 2, 4, message);
    assert(hash_result == 0x0f24729168d4450a5681beafa5e3a899ac28bd17bf5a4877dab37bcd834e1634);
}
