import Prim "mo:⛔";
import Buffer "mo:base/Buffer";
import Nat32 "mo:base/Nat32";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import Int "mo:base/Int";
import Prelude "mo:base/Prelude";

module {
    let INTERNAL_ERROR = "Internal error in Vector";

    let precalc : [(Nat32, Nat32, Nat32, Nat32)] = [(0x7FFF0000, 0xFFFF, 0x10, 0x17FFE), 
        (0x3FFF8000, 0x7FFF, 0xF, 0xFFFE), 
        (0x1FFF8000, 0x7FFF, 0xF, 0xBFFE), 
        (0xFFFC000, 0x3FFF, 0xE, 0x7FFE), 
        (0x7FFC000, 0x3FFF, 0xE, 0x5FFE), 
        (0x3FFE000, 0x1FFF, 0xD, 0x3FFE), 
        (0x1FFE000, 0x1FFF, 0xD, 0x2FFE), 
        (0xFFF000, 0xFFF, 0xC, 0x1FFE), 
        (0x7FF000, 0xFFF, 0xC, 0x17FE), 
        (0x3FF800, 0x7FF, 0xB, 0xFFE), 
        (0x1FF800, 0x7FF, 0xB, 0xBFE), 
        (0xFFC00, 0x3FF, 0xA, 0x7FE), 
        (0x7FC00, 0x3FF, 0xA, 0x5FE), 
        (0x3FE00, 0x1FF, 0x9, 0x3FE), 
        (0x1FE00, 0x1FF, 0x9, 0x2FE), 
        (0xFF00, 0xFF, 0x8, 0x1FE), 
        (0x7F00, 0xFF, 0x8, 0x17E), 
        (0x3F80, 0x7F, 0x7, 0xFE), 
        (0x1F80, 0x7F, 0x7, 0xBE), 
        (0xFC0, 0x3F, 0x6, 0x7E), 
        (0x7C0, 0x3F, 0x6, 0x5E), 
        (0x3E0, 0x1F, 0x5, 0x3E), 
        (0x1E0, 0x1F, 0x5, 0x2E), 
        (0xF0, 0xF, 0x4, 0x1E), 
        (0x70, 0xF, 0x4, 0x16), 
        (0x38, 0x7, 0x3, 0xE), 
        (0x18, 0x7, 0x3, 0xA), 
        (0xC, 0x3, 0x2, 0x6), 
        (0x4, 0x3, 0x2, 0x4), 
        (0x2, 0x1, 0x1, 0x2), 
        (0x0, 0x1, 0x1, 0x1), 
        (0x0, 0x0, 0x0, 0x0)
    ];

    func unwrap<X>(x : ?X) : X {
        switch (x) {
            case (null) Prim.trap(INTERNAL_ERROR);
            case (?value) value;
        };
    };

    public type Vector<X> = {
        var data_blocks : [var ?[var ?X]]; // the index block
        // fill levels
        var n_blocks : Nat; // number of existing data blocks = fill level of the index block
        var n_elements : Nat; // number of elements in last data block 
        // capacity
        var data_block_capacity : Nat; // capacity of the data blocks in the last super block (unit = elements)
    };

    func blocks_from_capacity<X>(initCapacity : Nat) : [var ?[var ?X]] {
        let (data_block, _) = locate(initCapacity - 1);
        var data_blocks = Array.init<?[var ?X]>(data_block + 1, null);
        var super_block = Nat32.fromNat(0);
        var last = 0;
        while (((1 << super_block) - 1) < Nat32.fromNat(initCapacity)) {
            let capacity = Nat32.toNat(1 << (super_block - (super_block >> 1)));
            let count = Nat32.toNat(1 << (super_block >> 1));

            var i = 0;
            while (i < count and last < data_blocks.size()) {
                data_blocks[last] := ?Array.init<?X>(capacity, null);
                i += 1;
                last += 1;
            };

            super_block += 1;
        };
        data_blocks;
    };

    public func init<X>(initCapacity : Nat) : Vector<X> = {
        var data_blocks = blocks_from_capacity(Nat.max(1, initCapacity));
        var n_blocks = 1;
        var n_elements = 0;
        var data_block_capacity = 1;
    };

    public func new<X>() : Vector<X> = {
        var data_blocks = [var]; 
        var n_blocks = 0;
        var n_elements = 0;
        var data_block_capacity = 0; // needs to be 0 so that first add triggers an allocation
    };

    public func clear<X>(vec : Vector<X>) {
        vec.data_blocks := [var];
        vec.n_blocks := 0;
        vec.n_elements := 0;
        vec.data_block_capacity := 0;
    };

    public func clone<X>(vec : Vector<X>) : Vector<X> = {
        var data_blocks = Array.tabulateVar<?[var ?X]>(
            vec.data_blocks.size(),
            func (i) = Option.map(
                vec.data_blocks[i],
                func(block : [var ?X]) : [var ?X] = Array.tabulateVar<?X>(block.size(), func(j) = block[j])
            )
        );
        var n_blocks = vec.n_blocks;
        var n_elements = vec.n_elements;
        var data_block_capacity = vec.data_block_capacity;
    };

    public func size<X>(vec : Vector<X>) : Nat {
        if (vec.n_blocks == 0) { return 0 }; 
        if (vec.n_blocks == 1) { return vec.n_elements };  

        let d : Nat = vec.n_blocks - 1; // index of the last block

        // We call all data blocks of the same capacity an "epoch". We number the epochs 0,1,2,...
        // A data block is in epoch e iff the data block has capacity 2^e.
        // Each epoch starting with epoch 1 spans exactly two super blocks.
        // Super block s falls in epoch ceil(s/2).

        // epoch of last data block
        let e : Nat = 32 - Nat32.toNat(Nat32.bitcountLeadingZero(Nat32.fromNat((d + 2)/3))); 

        // capacity of all prior epochs combined 
        let cap_before_e : Nat = 2 * 4**(e-1) - 1; 

        // data blocks in all prior epochs combined
        let blocks_before_e : Nat = 3 * 2**(e-1) - 2;

        // prior blocks in the same epoch
        let prior_blocks_in_e : Nat = d - blocks_before_e;

        return cap_before_e + prior_blocks_in_e * 2**e + vec.n_elements
    };

    func add_super_block_if_needed<X>(vec : Vector<X>) {
        let s = vec.n_blocks;
        if (s == 0) {
            vec.data_block_capacity := 1;
        }
        // the data block size doubles whenever s is of the form 3*2^n-2 for some n 
        else if (Nat.rem(s,3) == 1 and Nat32.bitcountNonZero(Nat32.fromNat((s+2)/3)) == 1) {
            vec.data_block_capacity *= 2;
        };
    };

    func grow_index_block_if_needed<X>(vec : Vector<X>) {
        if (vec.data_blocks.size() == vec.n_blocks) {
            let new_length = if (vec.n_blocks == 0) 1 else vec.n_blocks * 2;
            vec.data_blocks := Array.tabulateVar<?[var ?X]>(new_length, func(i) {
                if (i < vec.n_blocks) {
                    vec.data_blocks[i];
                } else {
                    null
                }
            });
        }
    };

    func add_data_block_if_needed<X>(vec : Vector<X>) {
        if (vec.data_block_capacity == vec.n_elements) {
            add_super_block_if_needed(vec);
            grow_index_block_if_needed(vec);

            if (Option.isNull(vec.data_blocks[vec.n_blocks])) {
                vec.data_blocks[vec.n_blocks] := ?Array.init<?X>(vec.data_block_capacity, null);
            };
            // else can we trap with internal error (should not happen)?

            vec.n_elements := 0;
            vec.n_blocks += 1;
        };
    };

    public func add<X>(vec : Vector<X>, element : X) {
        add_data_block_if_needed(vec);

        let last_data_block = unwrap(vec.data_blocks[vec.n_blocks - 1]);

        last_data_block[vec.n_elements] := ?element;
        vec.n_elements += 1;
    };

    /*
    func remove_super_block_if_needed<X>(vec : Vector<X>) {
        if (vec.super_block_size == 0) {
            vec.super_block_odd := not vec.super_block_odd;
            if (vec.super_block_odd) {
                vec.super_block_capacity /= 2;
            } else {
                vec.data_block_capacity /= 2;
            };
            vec.super_block_size := vec.super_block_capacity;
        };
    };
    */

    func shrink_index_block_if_needed<X>(vec : Vector<X>) {
        let quarter = vec.data_blocks.size() / 4;
        if (vec.n_blocks <= quarter) {
            vec.data_blocks := Array.tabulateVar<?[var ?X]>(quarter, func(i) {
                vec.data_blocks[i];
            });
        };
    };

    /*
    public func remove_data_block_if_needed<X>(vec : Vector<X>) {
        if (vec.n_elements == 0) {
            if (vec.n_blocks < vec.data_blocks.size() and not Option.isNull(vec.data_blocks[vec.n_blocks])) {
                vec.data_blocks[vec.n_blocks] := null;
            };

            shrink_index_block_if_needed(vec);
            if (vec.n_blocks > 1) {
                vec.super_block_size -= 1;
                remove_super_block_if_needed(vec);
                
                vec.n_blocks -= 1;
                vec.n_elements := vec.data_block_capacity;
            }
        };
    };

    public func removeLast<X>(vec : Vector<X>) : ?X {
        if (vec.size == 0) { 
            return null;
        };

        var last_data_block = unwrap(vec.data_blocks[vec.n_blocks - 1]);
        vec.size -= 1;
        vec.n_elements -= 1;
        let element = last_data_block[vec.n_elements];
        last_data_block[vec.n_elements] := null;

        remove_data_block_if_needed(vec);

        element;
    };
    */

    public func locate<X>(index : Nat) : (Nat, Nat) {
        // 32 super blocks have total capacity of 2^32-1 elements
        if (index >= 0xFFFFFFFF) {
            Prim.trap("Vector index in locate exceeds 32 super blocks")
        };
        let _index = Nat32.fromNat(index) + 1;
        let leadingZeros = Nat32.bitcountLeadingZero(_index);
        let (data_block_mask, element_mask, data_blocks_capacity_log, data_blocks_before) = precalc[Nat32.toNat(leadingZeros)];
        
        let data_block = (_index & data_block_mask) >> data_blocks_capacity_log;
        let index_in_data_block = _index & element_mask;

        (Nat32.toNat(data_blocks_before + data_block), Nat32.toNat(index_in_data_block));
    };

    public func get<X>(vec : Vector<X>, index : Nat) : X {
        let (a, b) = locate(index);
        if (a >= vec.n_blocks or (a == vec.n_blocks and b >= vec.n_elements)) {
            Prim.trap("Vector index out of bounds in get");
        };
        unwrap(unwrap(vec.data_blocks[a])[b]);
    };

    public func getOpt<X>(vec : Vector<X>, index : Nat) : ?X {
        let (a, b) = locate(index);
        if (a >= vec.n_blocks)
            null
        else 
            unwrap(vec.data_blocks[a])[b];
    };

    public func put<X>(vec : Vector<X>, index : Nat, value : X) {
        let (a, b) = locate(index);
        if (a >= vec.n_blocks or (a == vec.n_blocks and b >= vec.n_elements)) {
            Prim.trap("Vector index out of bounds in put");
        };
        unwrap(vec.data_blocks[a])[b] := ?value;
    };

    public func vals<X>(vec : Vector<X>) : { next : () -> ?X } = object {
        var index = 0;
        var data_block = 0;
        var in_data_block = 0;

        public func next() : ?X {
            if (index == size(vec)) {
                return null;
            };
            let element = unwrap(vec.data_blocks[data_block])[in_data_block];
            index += 1;
            in_data_block += 1;
            if (in_data_block == unwrap(vec.data_blocks[data_block]).size()) {
                data_block += 1;
                in_data_block := 0;
            };
            element;
        };
    };

    public func toArray<X>(vec : Vector<X>) : [X] = Array.tabulate<X>(size(vec), func(i) = get(vec, i));

    public func toVarArray<X>(vec : Vector<X>) : [var X] = Array.tabulateVar<X>(size(vec), func(i) = get(vec, i));
};
