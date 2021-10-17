// SPDX-License-Identifier: BCOM

pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./ISwapsPair.sol";
import "./ISwapsFactory.sol";
import "./ISwapsCallee.sol";

import "./SwapsHelper.sol";

contract SwapsERC20 is ISwapsERC20 {

    string public constant name = 'Bitcoin.com Swaps';
    string public constant symbol = 'BCOM-S';
    uint8 public constant decimals = 18;

    uint256 public totalSupply;

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    constructor() {
        uint256 chainId = block.chainid;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _mint(
        address _to,
        uint256 _value
    )
        internal
    {
        totalSupply =
        totalSupply + _value;

        balanceOf[_to] =
        balanceOf[_to] + _value;

        emit Transfer(
            address(0x0),
            _to,
            _value
        );
    }

    function _burn(
        address _from,
        uint256 _value
    )
        internal
    {
        totalSupply =
        totalSupply - _value;

        balanceOf[_from] =
        balanceOf[_from] - _value;

        emit Transfer(
            _from,
            address(0x0),
            _value
        );
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _value
    )
        private
    {
        allowance[_owner][_spender] = _value;

        emit Approval(
            _owner,
            _spender,
            _value
        );
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _value
    )
        private
    {
        balanceOf[_from] =
        balanceOf[_from] - _value;

        balanceOf[_to] =
        balanceOf[_to] + _value;

        emit Transfer(
            _from,
            _to,
            _value
        );
    }

    function approve(
        address _spender,
        uint256 _value
    )
        external
        returns (bool)
    {
        _approve(
            msg.sender,
            _spender,
            _value
        );

        return true;
    }

    function transfer(
        address _to,
        uint256 _value
    )
        external
        returns (bool)
    {
        _transfer(
            msg.sender,
            _to,
            _value
        );

        return true;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
        external
        returns (bool)
    {

        allowance[_from][msg.sender] =
        allowance[_from][msg.sender] - _value;

        _transfer(
            _from,
            _to,
            _value
        );

        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        require(
            deadline >= block.timestamp,
            'PERMIT_CALL_EXPIRED'
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );

        address recoveredAddress = ecrecover(
            digest,
            v,
            r,
            s
        );

        require(
            recoveredAddress != address(0) &&
            recoveredAddress == owner,
            'INVALID_SIGNATURE'
        );

        _approve(
            owner,
            spender,
            value
        );
    }
}

contract SwapsPair is ISwapsPair, SwapsERC20 {

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(
        keccak256(bytes('transfer(address,uint256)'))
    );

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    uint256 public kLast;
    uint256 private unlocked = 1;

    modifier lock() {
        require(
            unlocked == 1,
            'LOCKED'
        );
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves()
        public
        view
        returns (
            uint112,
            uint112,
            uint32
        )
    {
        return (
            reserve0,
            reserve1,
            blockTimestampLast
        );
    }

    function _safeTransfer(
        address token,
        address to,
        uint value
    )
        private
    {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }

    event Mint(
        address indexed sender,
        uint256 amount0,
        uint256 amount1
    );

    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    event Sync(
        uint112 reserve0,
        uint112 reserve1
    );

    constructor() SwapsERC20() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(
        address _token0,
        address _token1
    )
        external
    {
        require(
            msg.sender == factory,
            'FORBIDDEN'
        );

        token0 = _token0;
        token1 = _token1;
    }

    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    )
        private
    {
        require(
            balance0 <= U112_MAX &&
            balance1 <= U112_MAX,
            'OVERFLOW'
        );

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(uqdiv(encode(_reserve1), _reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(uqdiv(encode(_reserve0), _reserve1)) * timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        blockTimestampLast = blockTimestamp;

        emit Sync(
            reserve0,
            reserve1
        );
    }

    function _mintFee(
        uint112 _reserve0,
        uint112 _reserve1,
        uint256 _kLast
    )
        private
    {
        if (_kLast == 0) return;

        uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
        uint256 rootKLast = Math.sqrt(_kLast);

        if (rootK > rootKLast) {

            uint256 liquidity = totalSupply
                * (rootK - rootKLast)
                / (rootK * 5 + rootKLast);

            if (liquidity == 0) return;

            _mint(
                ISwapsFactory(factory).feeTo(),
                liquidity
            );
        }
    }

    function mint(
        address _to
    )
        external
        lock
        returns (uint256 liquidity)
    {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        _mintFee(
            _reserve0,
            _reserve1,
            kLast
        );

        uint256 _totalSupply = totalSupply;

        if (_totalSupply == 0) {

            liquidity = Math.sqrt(
                amount0 * amount1
            ) - MINIMUM_LIQUIDITY;

            _mint(
               address(0x0),
               MINIMUM_LIQUIDITY
            );

        } else {

            liquidity = Math.min(
                amount0 * _totalSupply / _reserve0,
                amount1 * _totalSupply / _reserve1
            );
        }

        require(
            liquidity > 0,
            'INSUFFICIENT_LIQUIDITY_MINTED'
        );

        _mint(
            _to,
            liquidity
        );

        _update(
            balance0,
            balance1,
            _reserve0,
            _reserve1
        );

        kLast = uint256(reserve0) * reserve1;

        emit Mint(
            msg.sender,
            amount0,
            amount1
        );
    }

    function burn(
        address _to
    )
        external
        lock
        returns (
            uint amount0,
            uint amount1
        )
    {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        address _token0 = token0;
        address _token1 = token1;

        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));

        uint256 liquidity = balanceOf[address(this)];

        _mintFee(
            _reserve0,
            _reserve1,
            kLast
        );

        uint256 _totalSupply = totalSupply;

        amount0 = liquidity * balance0 / _totalSupply;
        amount1 = liquidity * balance1 / _totalSupply;

        require(
            amount0 > 0 &&
            amount1 > 0,
            'INSUFFICIENT_LIQUIDITY_BURNED'
        );

        _burn(
            address(this),
            liquidity
        );

        _safeTransfer(
            _token0,
            _to,
            amount0
        );

        _safeTransfer(
            _token1,
            _to,
            amount1
        );

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(
            balance0,
            balance1,
            _reserve0,
            _reserve1
        );

        kLast = uint256(reserve0) * reserve1;

        emit Burn(
            msg.sender,
            amount0,
            amount1,
            _to
        );
    }

    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        bytes calldata _data
    )
        external
        lock
    {
        require(
            _amount0Out > 0 ||
            _amount1Out > 0,
            'INSUFFICIENT_OUTPUT_AMOUNT'
        );

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        require(
            _amount0Out < _reserve0 &&
            _amount1Out < _reserve1,
            'INSUFFICIENT_LIQUIDITY'
        );

        uint256 balance0;
        uint256 balance1;

        {
            address _token0 = token0;
            address _token1 = token1;

            if (_amount0Out > 0) _safeTransfer(_token0, _to, _amount0Out);
            if (_amount1Out > 0) _safeTransfer(_token1, _to, _amount1Out);

            if (_data.length > 0) ISwapsCallee(_to).swapsCall(
                msg.sender,
                _amount0Out,
                _amount1Out,
                _data
            );

            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint256 _amount0In = balance0 > _reserve0 - _amount0Out
            ? balance0 - (_reserve0 - _amount0Out)
            : 0;

        uint256 _amount1In = balance1 > _reserve1 - _amount1Out
            ? balance1 - (_reserve1 - _amount1Out)
            : 0;

        require(
            _amount0In > 0 || _amount1In > 0,
            'INSUFFICIENT_INPUT_AMOUNT'
        );

        {
            uint256 balance0Adjusted = balance0 * 1000 - (_amount0In * 3);
            uint256 balance1Adjusted = balance1 * 1000 - (_amount1In * 3);

            require(
                balance0Adjusted * balance1Adjusted >=
                uint256(_reserve0)
                    * _reserve1
                    * (1000**2)
            );
        }

        _update(
            balance0,
            balance1,
            _reserve0,
            _reserve1
        );

        emit Swap(
            msg.sender,
            _amount0In,
            _amount1In,
            _amount0Out,
            _amount1Out,
            _to
        );
    }

    function skim()
        external
        lock
    {
        address _token0 = token0;
        address _token1 = token1;
        address _feesTo = ISwapsFactory(factory).feeTo();

        _safeTransfer(
            _token0,
            _feesTo,
            IERC20(_token0).balanceOf(address(this)) - reserve0
        );

        _safeTransfer(
            _token1,
            _feesTo,
            IERC20(_token1).balanceOf(address(this)) - reserve1
        );
    }
}

contract SwapsFactory is ISwapsFactory {

    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;

    address[] public allPairs;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    constructor(
        address _feeToSetter
    ) {
        feeToSetter = _feeToSetter;
        feeTo = _feeToSetter;
    }

    function allPairsLength()
        external
        view
        returns (uint256)
    {
        return allPairs.length;
    }

    function pairCodeHash()
        external
        pure
        returns (bytes32)
    {
        return keccak256(
            type(SwapsPair).creationCode
        );
    }

    function createPair(
        address _tokenA,
        address _tokenB
    )
        external
        returns (address pair)
    {
        require(
            _tokenA != _tokenB,
            'IDENTICAL_ADDRESSES'
        );

        (address token0, address token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);

        require(
            token0 != address(0),
            'ZERO_ADDRESS'
        );

        require(
            getPair[token0][token1] == address(0),
            'PAIR_ALREADY_EXISTS'
        );

        bytes memory bytecode = type(SwapsPair).creationCode;

        bytes32 salt = keccak256(
            abi.encodePacked(
                token0,
                token1
            )
        );

        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        ISwapsPair(pair).initialize(
            token0,
            token1
        );

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        allPairs.push(pair);

        emit PairCreated(
            token0,
            token1,
            pair,
            allPairs.length
        );
    }

    function setFeeTo(
        address _feeTo
    )
        external
    {
        require(
            msg.sender == feeToSetter,
            'SwapsFactory: FORBIDDEN'
        );

        feeTo = _feeTo;
    }

    function setFeeToSetter(
        address _feeToSetter
    )
        external
    {
        require(
            msg.sender == feeToSetter,
            'SwapsFactory: FORBIDDEN'
        );

        feeToSetter = _feeToSetter;
    }
}

library Math {

    function min(
        uint _x,
        uint _y
    )
        internal
        pure
        returns (uint)
    {
        return _x < _y ? _x : _y;
    }

    function sqrt(
        uint _y
    )
        internal
        pure
        returns (uint z)
    {
        unchecked {
            if (_y > 3) {
                z = _y;
                uint x = _y / 2 + 1;
                while (x < z) {
                    z = x;
                    x = (_y / x + x) / 2;
                }
            } else if (_y != 0) {
                z = 1;
            }
        }
    }
}
