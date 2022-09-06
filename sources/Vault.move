module Vault::SimpleVault {
    use std::signer;

    use aptos_framework::account;

    //Errors
    const EINVALID_SIGNER: u64 = 0;
    const EADMIN_ALREADY_EXISTS: u64 = 1;
    const EVAULTINFO_NOT_CREATED: u64 = 2;
    const EADMIN_NOT_CREATED: u64 = 3;

    // Resources
    struct Admin has key {
        resource_account: address
    }

    struct VaultInfo has key {
        pause: bool,
        authority: address
    }
    
    public entry fun create_admin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @Vault, EINVALID_SIGNER);
        assert!(!exists<Admin>(admin_addr), EADMIN_ALREADY_EXISTS);

        // Creating a resource account for the vault to store global information like pause status and coin address
        let seed = b"admin";
        let (vault_resource, _vault_resource_signer_cap) = account::create_resource_account(admin, seed);
        let vault_resource_addr = signer::address_of(&vault_resource);
        move_to<Admin>(admin, Admin{resource_account: vault_resource_addr});
        move_to<VaultInfo>(&vault_resource, VaultInfo{pause: true, authority: admin_addr});
    }

    #[test_only]
    public fun get_resource_account(source: address, seed: vector<u8>): address {
        use std::hash;
        use std::bcs;
        use std::vector;
        use aptos_framework::byte_conversions;
        let bytes = bcs::to_bytes(&source);
        vector::append(&mut bytes, seed);
        let addr = byte_conversions::to_address(hash::sha3_256(bytes));
        addr
    }

    #[test(admin = @Vault)]
    public fun can_init_admin(admin: signer)  {
        create_admin(&admin);
        let admin_addr = signer::address_of(&admin);
        assert!(exists<Admin>(admin_addr), EADMIN_NOT_CREATED);

        let seed = b"admin";
        let vault_resource_addr = get_resource_account(admin_addr, seed);
        assert!(exists<VaultInfo>(vault_resource_addr), EVAULTINFO_NOT_CREATED);
    }
}