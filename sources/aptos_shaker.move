
// This Aptos Move module implements a blockchain-based dice game called Aptos Shaker. 
// It utilizes the Aptos blockchain's features such as accounts, events, and tokens to create a game where users can bet on dice rolls.

module game::aptos_shaker {    
    use std::signer;            
    use std::error;
    use aptos_framework::account;                
    use aptos_framework::randomness;
    use aptos_framework::timestamp;            
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::coin;    
    use std::string::{Self, String};
    use aptos_token::token::{Self};
    use aptos_std::simple_map::{Self, SimpleMap};
    use std::option::{Self, Option};
    use std::vector;
        
    // constants for config
    const FEE_DENOMINATOR: u64 = 100000;    
    const INVITER_FEE_RATE: u64 = 10000; // Specifies that 10% of the winner's fee goes to the inviter
    
    // Error codes for handling various exceptions in the game

    const EKEY_NOT_EXISTS: u64 = 1;
    const ENO_INVITE_RIGHTS:u64 = 2;
    const EALREADY_INVITED:u64 = 3;
    const ENO_PLAYER_INFO:u64 = 4;
    const ENOT_AUTHORIZED: u64 = 5;    
    
    // Metadata for the invitation token collection used in the game.
    const COLLECTION_NAME:vector<u8> = b"Aptos Shaker";
    const COLLECTION_DESCRIPTION:vector<u8> = b"Aptos Shaker is a project that energizes the Aptos Ecosystem. If you have received this collection, it means someone has invited you to Aptos Shaker. If you participate in the Aptos Shaker game, you can enjoy the game with lower fees.";

    // Data structures for storing game information
    struct ReferralInfo has key, store {
        inviter: address,   
        invitee: address,        
    }

    struct PlayerInfo has key, store {
        play_count: u64,
        invite_rights: u64,
        points:u64
    }
    
    struct AptosShakerGame has store, key {          
        signer_cap: account::SignerCapability,
        fee_rate:u64, 
        fee_payee:address,        
        referral_infos: SimpleMap<address, ReferralInfo>,
        player_infos: SimpleMap<address, PlayerInfo>,
        roll_events: EventHandle<RollEvent>, 
        player_info_update_events: EventHandle<PlayerInfoUpdateEvent>,
        last_game_time:u64,
        jackpot_amount:u64,
        game_count: u64
    }        
    
    struct MultipleInfo has key {
        multiple_map: SimpleMap<u64,u64>,
    }

    struct RollEvent has key, drop, store {
        dice_one: u64,
        dice_two: u64,
        multiple: u64,
        game_time: u64,
        game_type: u64,
        jackpot: bool,
        accumulated_jackpot: u64,
        game_count: u64,
    }    

    struct PlayerInfoUpdateEvent has drop, store {
        player_address: address,
        play_count: u64,
        invite_rights: u64,
        points: u64,
    }

    entry fun admin_withdraw<CoinType>(sender: &signer, price: u64) acquires AptosShakerGame {
        let sender_addr = signer::address_of(sender);
        let resource_signer = get_resource_account_cap(sender_addr);                        
        let coins = coin::withdraw<CoinType>(&resource_signer, price);                
        coin::deposit(sender_addr, coins);
    }

    entry fun admin_deposit<CoinType>(sender: &signer, price: u64) acquires AptosShakerGame {
        let sender_addr = signer::address_of(sender);
        let resource_signer = get_resource_account_cap(sender_addr);                 
        let resource_signer_addr = signer::address_of(&resource_signer);
        let coins = coin::withdraw<CoinType>(sender, price);                
        coin::deposit(resource_signer_addr, coins); 
    }    

    entry fun modify_multiple_value<CoinType>(sender: &signer, new_value: u64, target_sum: u64) acquires MultipleInfo {
        let sender_addr = signer::address_of(sender);        
        if (exists<MultipleInfo>(sender_addr)) {
            let multiple_info = borrow_global_mut<MultipleInfo>(sender_addr);                        
            if (simple_map::contains_key(&multiple_info.multiple_map, &target_sum)) {
                simple_map::add(&mut multiple_info.multiple_map, target_sum, new_value);
            };
        };
    }

    fun get_resource_account_cap(resource_account_address : address) : signer acquires AptosShakerGame {
        let minter = borrow_global<AptosShakerGame>(resource_account_address);
        account::create_signer_with_capability(&minter.signer_cap)
    }

    public entry fun token_store(sender:&signer) {
        token::initialize_token_store(sender);
        token::opt_in_direct_transfer(sender, true);
    }    
        
        
    entry fun init_game<CoinType>(sender: &signer, fee_payee: address, fee_rate: u64) acquires MultipleInfo {         
        let sender_addr = signer::address_of(sender);                
        let (resource_signer, signer_cap) = account::create_resource_account(sender, x"01");
            token::initialize_token_store(&resource_signer);

        if(!coin::is_account_registered<CoinType>(signer::address_of(&resource_signer))){
            coin::register<CoinType>(&resource_signer);
        };

        if (!exists<AptosShakerGame>(sender_addr)) {
            move_to(sender, MultipleInfo { multiple_map: simple_map::create()});
            let maps = borrow_global_mut<MultipleInfo>(sender_addr);

            // In shaker betting games, achieving a sum of 2 or 12 is quite rare, considering you're using two standard 6-sided shaker. There are 36 possible combinations when rolling two shaker, and only one combination can produce a sum of 2 (1+1), and similarly, only one combination results in a sum of 12 (6+6). This means the probability of rolling either 2 or 12 is 1 in 36, or about 2.78%.
            // Given this rarity, it's reasonable to offer players a significantly higher payout for these outcomes to add excitement and to reward the low probability event. For example, in traditional casino games like Craps, it's not uncommon to see payouts that offer 30:1 or even higher for specific rare outcomes. However, offering too high a payout can disrupt the game's economic balance and affect its profitability.
            // For a dice betting game, offering a payout multiplier of about 10 to 15 times the bet for rolling a 2 or 12 strikes a good balance. It provides a substantial reward for the rare event, enhancing player satisfaction, while also maintaining the financial stability of the game. Nonetheless, the exact multiplier should be carefully considered in the context of the game's overall odds, the expected return to player (RTP), and the competitive landscape of the market.
            // simple_map::add(&mut maps.multiple_map, 2, 360);
            // simple_map::add(&mut maps.multiple_map, 3, 180);
            // simple_map::add(&mut maps.multiple_map, 4, 120);
            // simple_map::add(&mut maps.multiple_map, 5, 90);
            // simple_map::add(&mut maps.multiple_map, 6, 72);
            // simple_map::add(&mut maps.multiple_map, 7, 60);
            // simple_map::add(&mut maps.multiple_map, 8, 72);
            // simple_map::add(&mut maps.multiple_map, 9, 90);
            // simple_map::add(&mut maps.multiple_map, 10, 120);
            // simple_map::add(&mut maps.multiple_map, 11, 180);
            // simple_map::add(&mut maps.multiple_map, 12, 360);   
            simple_map::add(&mut maps.multiple_map, 2, 100);
            simple_map::add(&mut maps.multiple_map, 3, 90);
            simple_map::add(&mut maps.multiple_map, 4, 80);
            simple_map::add(&mut maps.multiple_map, 5, 60);
            simple_map::add(&mut maps.multiple_map, 6, 40);
            simple_map::add(&mut maps.multiple_map, 7, 30);
            simple_map::add(&mut maps.multiple_map, 8, 40);
            simple_map::add(&mut maps.multiple_map, 9, 60);
            simple_map::add(&mut maps.multiple_map, 10, 80);
            simple_map::add(&mut maps.multiple_map, 11, 90);
            simple_map::add(&mut maps.multiple_map, 12, 100);            
        };

        if(!exists<AptosShakerGame>(sender_addr)){
            move_to(sender, AptosShakerGame {
                signer_cap,
                fee_rate,
                fee_payee,                                
                referral_infos: simple_map::create(),
                player_infos: simple_map::create(),
                roll_events: account::new_event_handle<RollEvent>(sender),
                player_info_update_events: account::new_event_handle<PlayerInfoUpdateEvent>(sender),
                last_game_time: timestamp::now_seconds(),
                jackpot_amount: 0,
                game_count: 0,
            });
        };

        let mutate_setting = vector<bool>[ true, true, true ]; // TODO should check before deployment.
        let collection_uri = string::utf8(b"https://aptos-shaker.s3.ap-northeast-2.amazonaws.com/invitation_letter_image.webp");
        token::create_collection(&resource_signer, string::utf8(COLLECTION_NAME), string::utf8(COLLECTION_DESCRIPTION), collection_uri,0, mutate_setting);                                                                     
    }

    #[randomness]
    entry fun game_even_odd<CoinType>(sender: &signer, game_address:address, guess_params_is_even: bool, bet_price:u64) acquires AptosShakerGame  {
        // assert!(bet_price >= 1000000, error::permission_denied(ENOT_AUTHORIZED));
        assert!(bet_price == 10000000 || bet_price == 100000000 || bet_price == 500000000 || bet_price == 1500000000, error::permission_denied(ENOT_AUTHORIZED));
        // assert!(bet_price == 50000000000 || bet_price == 500000000000 || bet_price == 2500000000000, error::permission_denied(ENOT_AUTHORIZED));
        let sender_addr = signer::address_of(sender);
        let resource_signer = get_resource_account_cap(game_address);
        let dice_game = borrow_global_mut<AptosShakerGame>(game_address); 
        
        let resource_account_address = signer::address_of(&resource_signer);     
        // let final_number_1 = randomness::u64_range(1, 7);
        // let final_number_2 = randomness::u64_range(1, 7); 

        assert!(coin::balance<CoinType>(sender_addr) >= bet_price, error::permission_denied(ENOT_AUTHORIZED));
        assert!(coin::balance<CoinType>(resource_account_address) >= bet_price * 2, error::permission_denied(ENOT_AUTHORIZED));   
        
        let _fee_rate = dice_game.fee_rate;
        let _fee_payee = dice_game.fee_payee;

        // jackpot 
        let jackpot_fee = bet_price * 1000 / FEE_DENOMINATOR; // 1% of bet price
        let jackpot_coins = coin::withdraw<CoinType>(sender, jackpot_fee);
        coin::deposit(resource_account_address, jackpot_coins);
        dice_game.jackpot_amount = dice_game.jackpot_amount + jackpot_fee;
        let jackpot = update_play_count_and_check_invite(dice_game, sender_addr, 2);
        if(jackpot) {
            let jackpot_win_coins = coin::withdraw<CoinType>(&resource_signer, dice_game.jackpot_amount);            
            coin::deposit(sender_addr, jackpot_win_coins);
            dice_game.jackpot_amount = 0;
        };

        let _total_fee = bet_price * _fee_rate / FEE_DENOMINATOR;
        let game_fee_coin = coin::withdraw<CoinType>(sender, _total_fee);
        let game_fee = _total_fee / 2; 
        let game_operation_fee = coin::extract(&mut game_fee_coin, game_fee);        
        coin::deposit(resource_account_address, game_operation_fee);
        coin::deposit(_fee_payee, game_fee_coin);

        let inviter_fee = _total_fee * INVITER_FEE_RATE / FEE_DENOMINATOR;        
        let invitee_fee = inviter_fee;        
        
        let inviter_address = get_inviter_address(dice_game, sender_addr);
        if(option::is_some(&mut inviter_address)) {
            let invieter_add = option::extract(&mut inviter_address);        
            let inviter_coin = coin::withdraw<CoinType>(&resource_signer, inviter_fee);
            let invitee_coin = coin::withdraw<CoinType>(&resource_signer, invitee_fee);                
            coin::deposit(invieter_add, inviter_coin);
            coin::deposit(sender_addr, invitee_coin);
        };        
        
        let win_price = bet_price - _total_fee;
        let lose_fee = bet_price - _total_fee;
        
        let (final_number_1, final_number_2) = randomly_pick_number();
        let sum = final_number_1 + final_number_2;
        let is_even = (sum % 2) == 0;
        let guessed_even = guess_params_is_even;        
        if(is_even == guessed_even) {                                                                                                            
            let vault_coin = coin::withdraw<CoinType>(&resource_signer, win_price);
            coin::deposit(sender_addr, vault_coin);
        } else {                
           let coins = coin::withdraw<CoinType>(sender, lose_fee);
           coin::deposit(resource_account_address, coins);
        };                        
                        
        event::emit_event(&mut dice_game.roll_events, RollEvent { 
            dice_one: final_number_1,
            dice_two: final_number_2, 
            multiple: 2,            
            game_time: timestamp::now_seconds(),
            game_type: 1,
            jackpot: jackpot,
            accumulated_jackpot: dice_game.jackpot_amount,
            game_count: dice_game.game_count,
        });
    }
    
    #[randomness]
    entry fun game_sum<CoinType>(sender: &signer, game_address:address, guess_params_sum: u64, bet_price:u64) acquires AptosShakerGame, MultipleInfo {                            
        // assert!(bet_price >= 1000000, error::permission_denied(ENOT_AUTHORIZED));
        assert!(bet_price == 10000000 || bet_price == 100000000 || bet_price == 500000000 || bet_price == 1500000000, error::permission_denied(ENOT_AUTHORIZED));
        // assert!(bet_price == 50000000000 || bet_price == 500000000000 || bet_price == 2500000000000, error::permission_denied(ENOT_AUTHORIZED));
        let now_second = timestamp::now_seconds();        
        let sender_addr = signer::address_of(sender);
        
        let resource_signer = get_resource_account_cap(game_address);
        let resource_account_address = signer::address_of(&resource_signer);

        assert!(coin::balance<CoinType>(sender_addr) >= bet_price, error::permission_denied(ENOT_AUTHORIZED));
        assert!(coin::balance<CoinType>(resource_account_address) >= bet_price * 2, error::permission_denied(ENOT_AUTHORIZED));

        let dice_game = borrow_global_mut<AptosShakerGame>(game_address);                        
        let maps = borrow_global<MultipleInfo>(game_address);
        assert!(simple_map::contains_key(&maps.multiple_map, &guess_params_sum), EKEY_NOT_EXISTS);
        
        let multiple = *simple_map::borrow(&maps.multiple_map, &guess_params_sum);
        
        // dynamic multiplier                
        let last_game_time = dice_game.last_game_time;       
        let elapsed_time = now_second - last_game_time; 
        let delta = multiple / 3;    

        // The delta value increases every hour, and after 3 hours, the multiple will double.
        let dynamic_multiplier = if(elapsed_time > 36000) { delta * (elapsed_time / 36000) } else { 0 };        
        if(dynamic_multiplier > 10) { // max 10x
            dynamic_multiplier = 10;
        };
        let applied_multiple = if(dynamic_multiplier > 0) { multiple + dynamic_multiplier } else { multiple };                         
        
        // jackpot 
        let jackpot_fee = bet_price * 1000 / FEE_DENOMINATOR; // 1% of bet price
        let jackpot_coins = coin::withdraw<CoinType>(sender, jackpot_fee);
        coin::deposit(resource_account_address, jackpot_coins);
        dice_game.jackpot_amount = dice_game.jackpot_amount + jackpot_fee;        
        let jackpot = update_play_count_and_check_invite(dice_game, sender_addr, multiple / 10);
        if(jackpot) {
            let jackpot_win_coins = coin::withdraw<CoinType>(&resource_signer, dice_game.jackpot_amount);            
            coin::deposit(sender_addr, jackpot_win_coins);
            dice_game.jackpot_amount = 0;
        };

        let _fee_rate = dice_game.fee_rate;
        let _fee_payee = dice_game.fee_payee;
        let _total_fee = bet_price * _fee_rate / FEE_DENOMINATOR;
        let game_fee_coin = coin::withdraw<CoinType>(sender, _total_fee);
        let game_fee = _total_fee / 2; 
        let game_operation_fee = coin::extract(&mut game_fee_coin, game_fee);        
        coin::deposit(resource_account_address, game_operation_fee);
        coin::deposit(_fee_payee, game_fee_coin);        

        let inviter_fee = _total_fee * INVITER_FEE_RATE / FEE_DENOMINATOR;
        let invitee_fee = inviter_fee;
        let inviter_address = get_inviter_address(dice_game, sender_addr);

        if(option::is_some(&mut inviter_address)) {
            let invieter_add = option::extract(&mut inviter_address);
            let inviter_coin = coin::withdraw<CoinType>(&resource_signer, inviter_fee);
            let invitee_coin = coin::withdraw<CoinType>(&resource_signer, invitee_fee);
            coin::deposit(invieter_add, inviter_coin);
            coin::deposit(sender_addr, invitee_coin);
        };                   

        // let final_number_1 = randomness::u64_range(1, 7);
        // let final_number_2 = randomness::u64_range(1, 7);   
        
        
        let win_price = calculate_win_price(bet_price, applied_multiple, _total_fee); // applied dynamic multiplier                
        let loser_fee = bet_price - _total_fee;
        let (final_number_1, final_number_2) = randomly_pick_number();
        let sum = final_number_1 + final_number_2;            
        if(guess_params_sum == sum) {                                                
            let vault_coin = coin::withdraw<CoinType>(&resource_signer, win_price);                            
            coin::deposit(sender_addr, vault_coin);                
        } else {
            let coins = coin::withdraw<CoinType>(sender, loser_fee);
            coin::deposit(resource_account_address, coins);                
        };                     
        dice_game.last_game_time = now_second;
        
        event::emit_event(&mut dice_game.roll_events, RollEvent { 
            dice_one: final_number_1,
            dice_two: final_number_2,
            multiple: applied_multiple,
            game_time: now_second,
            game_type: 2,
            jackpot: jackpot,
            accumulated_jackpot: dice_game.jackpot_amount,
            game_count: dice_game.game_count,           
        });
    }

    entry fun invite(sender: &signer,game_address:address, invitee_address: address) acquires AptosShakerGame {                
        let player_address = signer::address_of(sender);
        assert!(player_address == game_address, error::permission_denied(ENOT_AUTHORIZED));        
        let referral_info = ReferralInfo {
            inviter: signer::address_of(sender),
            invitee: invitee_address            
        };

        let resource_signer = get_resource_account_cap(game_address);
        let resource_signer_addr = signer::address_of(&resource_signer);
        let dice_game = borrow_global_mut<AptosShakerGame>(game_address);        
        assert!(simple_map::contains_key(&dice_game.player_infos, &player_address), ENO_PLAYER_INFO);
        let player_info = simple_map::borrow_mut(&mut dice_game.player_infos, &player_address);
        assert!(player_info.invite_rights > 0, ENO_INVITE_RIGHTS);
        assert!(!simple_map::contains_key(&dice_game.referral_infos, &invitee_address), EALREADY_INVITED);
        simple_map::add(&mut dice_game.referral_infos, invitee_address, referral_info);        
        player_info.invite_rights = player_info.invite_rights - 1;
        
        let i = 0;
        let token_name = string::utf8(COLLECTION_NAME);
        while (i <= 9999) {
            let new_token_name = string::utf8(COLLECTION_NAME);
            string::append_utf8(&mut new_token_name, b" #");
            let count_string = to_string((i as u128));
            string::append(&mut new_token_name, count_string);                                
            if(!token::check_tokendata_exists(resource_signer_addr, string::utf8(COLLECTION_NAME), new_token_name)) {
                token_name = new_token_name;                
                break
            };
            i = i + 1;
        };
        
        let uri = string::utf8(b"https://aptos-shaker.s3.ap-northeast-2.amazonaws.com/invitation_letter_image.webp");
        let token_data_id = token::create_tokendata(
                &resource_signer,
                string::utf8(COLLECTION_NAME),
                token_name,
                string::utf8(COLLECTION_DESCRIPTION),
                0,
                uri, 
                resource_signer_addr, // royalty fee to                
                FEE_DENOMINATOR,
                1000, 
                // we don't allow any mutation to the token
                token::create_token_mutability_config(
                   &vector<bool>[ false, false, false, false, true ]
                ),
                // type
                vector<String>[],  // property_keys                
                vector<vector<u8>>[],  // values 
                vector<String>[],
        );        
        if (token::get_direct_transfer(invitee_address)) {
            token::mint_token_to(&resource_signer,invitee_address, token_data_id, 1);                
        };                

        let update_event = PlayerInfoUpdateEvent {
            player_address: player_address,
            play_count: player_info.play_count,
            invite_rights: player_info.invite_rights,
            points: player_info.points
        };
        event::emit_event(&mut dice_game.player_info_update_events, update_event);
    }
    
                       

    fun update_play_count_and_check_invite(dice_game: &mut AptosShakerGame, player_address: address, points: u64) : bool {        
        if (!simple_map::contains_key(&dice_game.player_infos, &player_address)) {            
            let new_player_info = PlayerInfo { play_count: 0, invite_rights: 0, points: 0 };
            simple_map::add(&mut dice_game.player_infos, player_address, new_player_info);
        };
        
        let player_info = simple_map::borrow_mut(&mut dice_game.player_infos, &player_address);
        player_info.play_count = player_info.play_count + 1;
        player_info.points = player_info.points + points;
        
        // dice_game.jackpot_amount        
        dice_game.game_count = dice_game.game_count + 1;
        let jackpot = false;
        if (dice_game.game_count % 100 == 0) {
            // check jackpot game count  
            jackpot = true;          
        };
        
        if (player_info.play_count % 20 == 0) {
            player_info.invite_rights = player_info.invite_rights + 1;
        };


        let update_event = PlayerInfoUpdateEvent {
            player_address: player_address,
            play_count: player_info.play_count,
            invite_rights: player_info.invite_rights,
            points: player_info.points
        };

        event::emit_event(&mut dice_game.player_info_update_events, update_event);
        jackpot
    }

    fun calculate_win_price(bet_price: u64, multiple: u64, total_fee: u64) : u64 {
       ((bet_price * multiple) / 10) - total_fee
    }
    

   fun get_inviter_address(game: &AptosShakerGame, invitee_address: address): Option<address> {
        if (simple_map::contains_key(&game.referral_infos, &invitee_address)) {
            let referral_info_ref = simple_map::borrow(&game.referral_infos, &invitee_address);            
            option::some(referral_info_ref.inviter)
        } else {
            option::none()
        }
    }
    
    fun randomly_pick_number(): (u64,u64) {            
        let final_number_1 = randomness::u64_range(1, 7);
        let final_number_2 = randomness::u64_range(1, 7);

        (final_number_1, final_number_2)
    }        
    
    public fun to_string(value: u128): String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }   
}
