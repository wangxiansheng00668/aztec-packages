use crate::{
    abis::{
    nullifier_key_validation_request::NullifierKeyValidationRequestContext,
    public_data_read::PublicDataRead, read_request::ReadRequestContext, side_effect::SideEffect
},
    constants::{
    MAX_NOTE_HASH_READ_REQUESTS_PER_TX, MAX_NULLIFIER_READ_REQUESTS_PER_TX,
    MAX_NULLIFIER_NON_EXISTENT_READ_REQUESTS_PER_TX, MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_TX,
    MAX_PUBLIC_DATA_READS_PER_TX
}
};

// TODO - Use specific structs for private and public: PrivateValidationRequests vs PublicValidationRequests
struct ValidationRequests {
    note_hash_read_requests: [SideEffect; MAX_NOTE_HASH_READ_REQUESTS_PER_TX],
    nullifier_read_requests: [ReadRequestContext; MAX_NULLIFIER_READ_REQUESTS_PER_TX],
    nullifier_non_existent_read_requests: [ReadRequestContext; MAX_NULLIFIER_NON_EXISTENT_READ_REQUESTS_PER_TX],
    nullifier_key_validation_requests: [NullifierKeyValidationRequestContext; MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_TX],
    public_data_reads: [PublicDataRead; MAX_PUBLIC_DATA_READS_PER_TX],
}
