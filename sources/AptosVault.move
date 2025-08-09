module MyModule::VaultSystem {
    use aptos_framework::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account;
    use aptos_framework::event;

    /// Error codes
    const E_NOT_ADMIN: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_VAULT_ALREADY_EXISTS: u64 = 3;
    const E_NO_ALLOCATION: u64 = 4;

    /// Events
    struct TokensDepositedEvent has drop, store {
        amount: u64,
    }

    struct TokensAllocatedEvent has drop, store {
        recipient: address,
        amount: u64,
    }

    struct TokensClaimedEvent has drop, store {
        claimer: address,
        amount: u64,
    }

    struct TokensWithdrawnEvent has drop, store {
        amount: u64,
    }

    /// Main vault structure
    struct Vault has key {
        admin: address,
        vault_address: address,
        total_balance: u64,
        allocated_balance: u64,
        tokens_deposited_events: event::EventHandle<TokensDepositedEvent>,
        tokens_allocated_events: event::EventHandle<TokensAllocatedEvent>,
        tokens_claimed_events: event::EventHandle<TokensClaimedEvent>,
        tokens_withdrawn_events: event::EventHandle<TokensWithdrawnEvent>,
    }



    /// Vault signer capability
    struct VaultSignerCapability has key {
        cap: account::SignerCapability,
    }

    /// Initialize the vault system
    fun init_module(admin: &signer) {
        let admin_address = signer::address_of(admin);
        
        // Create vault account
        let (vault_signer, vault_cap) = account::create_resource_account(admin, b"vault");
        let vault_address = signer::address_of(&vault_signer);

        // Register AptosCoin for the vault
        coin::register<AptosCoin>(&vault_signer);

        // Create vault resource
        let vault = Vault {
            admin: admin_address,
            vault_address,
            total_balance: 0,
            allocated_balance: 0,
            tokens_deposited_events: account::new_event_handle<TokensDepositedEvent>(&vault_signer),
            tokens_allocated_events: account::new_event_handle<TokensAllocatedEvent>(&vault_signer),
            tokens_claimed_events: account::new_event_handle<TokensClaimedEvent>(&vault_signer),
            tokens_withdrawn_events: account::new_event_handle<TokensWithdrawnEvent>(&vault_signer),
        };

        move_to(&vault_signer, vault);

        // Store signer capability with admin
        let vault_signer_cap = VaultSignerCapability { cap: vault_cap };
        move_to(admin, vault_signer_cap);
    }

    /// Deposit tokens into the vault
    public entry fun deposit_tokens(admin: &signer, vault_address: address, amount: u64) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);
        
        coin::transfer<AptosCoin>(admin, vault.vault_address, amount);
        vault.total_balance = vault.total_balance + amount;
        event::emit_event(&mut vault.tokens_deposited_events, TokensDepositedEvent { amount });
    }

    /// Allocate tokens to a recipient (simplified version)
    public entry fun allocate_tokens(admin: &signer, vault_address: address, recipient: address, amount: u64) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);
        assert!(vault.total_balance - vault.allocated_balance >= amount, E_INSUFFICIENT_BALANCE);

        vault.allocated_balance = vault.allocated_balance + amount;

        // For this simplified version, we just track total allocated balance
        // In a full implementation, you'd want individual user allocation tracking

        event::emit_event(&mut vault.tokens_allocated_events, TokensAllocatedEvent { recipient, amount });
    }

    /// Withdraw unallocated tokens
    public entry fun withdraw_tokens(admin: &signer, vault_address: address, amount: u64) acquires Vault, VaultSignerCapability {
        let vault = borrow_global_mut<Vault>(vault_address);
        assert!(vault.admin == signer::address_of(admin), E_NOT_ADMIN);
        
        let available_balance = vault.total_balance - vault.allocated_balance;
        assert!(available_balance >= amount, E_INSUFFICIENT_BALANCE);

        vault.total_balance = vault.total_balance - amount;

        // Transfer tokens from vault to admin
        let vault_signer_cap = borrow_global<VaultSignerCapability>(vault.admin);
        let vault_signer = account::create_signer_with_capability(&vault_signer_cap.cap);
        coin::transfer<AptosCoin>(&vault_signer, vault.admin, amount);

        event::emit_event(&mut vault.tokens_withdrawn_events, TokensWithdrawnEvent { amount });
    }

    #[view]
    /// View function: Get vault info
    public fun get_vault_info(vault_address: address): (address, u64, u64) acquires Vault {
        let vault = borrow_global<Vault>(vault_address);
        (vault.admin, vault.total_balance, vault.allocated_balance)
    }

    /// Transfer ownership to a new admin
    public entry fun transfer_ownership(current_admin: &signer, vault_address: address, new_admin: address) acquires Vault {
        let vault = borrow_global_mut<Vault>(vault_address);
        assert!(vault.admin == signer::address_of(current_admin), E_NOT_ADMIN);
        
        vault.admin = new_admin;
    }
}