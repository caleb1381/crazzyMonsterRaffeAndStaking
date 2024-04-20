// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract NFTRaffle is ReentrancyGuard, ERC721Holder, Ownable {
    // state variables;
    using SafeERC20 for IERC20;

    IERC721 immutable mapNFT;

    uint256 public raffleIdCounter;
    uint256[] public activeRaffleIDs;

    struct Raffle {
        address NFTAddress;
        uint256 tokenId;
        uint256 maxTicketPerUser;
        uint256 totalTicketsSold;
        address[] players; // to keep track of all the players
        address[] playerSelector; // to keep track of all tickets bought per users
        uint256 entryCost;
        uint256 raffleId;
        uint256 maxTickets; // total supply of tickets for the raffle
        uint256 endTimestamp;
        address winner;
        bool raffleStatus;
    }

    mapping(uint256 => Raffle) public raffles;

    event NFTPrizeClaimed(uint256 indexed raffleId, address indexed winner);
    event RaffleCreated(uint256 indexed raffleId);
    event NewEntry(
        uint256 indexed raffleId,
        address indexed participant,
        uint256 numberOfTickets
    );
    event RaffleEnded(
        uint256 indexed raffleId,
        address indexed winner,
        uint256 totalTicketsSold
    );

    constructor(address _mapNFTAddress) Ownable(msg.sender) {
        mapNFT = IERC721(_mapNFTAddress); // this set the contract address of the map nft
    }

    function transferNFT(
        address _nftAddress,
        uint256 _tokenId,
        address _from,
        address _to
    ) private onlyOwner {
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _from,
            "Not owner of NFT"
        );

        IERC721(_nftAddress).safeTransferFrom(_from, _to, _tokenId, "");
    }

    // create raffle

    function createRaffle(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _maxTicketsPerUser,
        uint256 _endTimestamp,
        uint256 _entryCost,
        uint256 _maxTickets
    ) public onlyOwner {
        // check if the end time provided is not in the past
        require(
            _endTimestamp > block.timestamp,
            "End timestamp must be in the future"
        );

        raffleIdCounter += 1;

        uint256 raffleId = raffleIdCounter;

        raffles[raffleId] = Raffle({
            NFTAddress: _nftAddress,
            tokenId: _tokenId,
            maxTicketPerUser: _maxTicketsPerUser,
            totalTicketsSold: 0,
            players: new address[](0),
            playerSelector: new address[](0),
            entryCost: _entryCost,
            raffleId: raffleId,
            maxTickets: _maxTickets,
            endTimestamp: _endTimestamp,
            winner: address(0),
            raffleStatus: true
        });

        transferNFT(_nftAddress, _tokenId, msg.sender, address(this));

        activeRaffleIDs.push(raffleId);

        emit RaffleCreated(raffleId);
    }

    // join raffle

    function joinRaffle(
        uint256 raffleId,
        uint256 numOfTickets,
        address _token
    ) public nonReentrant {
        Raffle storage raffle = raffles[raffleId];
        require(block.timestamp < raffle.endTimestamp, "Ended");
        require(
            numOfTickets > 0,
            "ticket to be bought should be greater than 0"
        );
        require(
            numOfTickets + raffle.totalTicketsSold < raffle.maxTickets,
            "Sold out"
        );
        if (mapNFT.balanceOf(msg.sender) > 0) {
            freeRaffleForMapNFTHolder(raffleId);
        } else {
            buyRaffle(_token, raffleId, numOfTickets);
        }
        for (uint256 i = 0; i < numOfTickets; i++) {
            raffle.totalTicketsSold++;
            raffle.playerSelector.push(msg.sender);
        }
        emit NewEntry(raffleId, msg.sender, numOfTickets);
    }

    // function buyRaffle(address _token, uint256 _raffleId, uint256 _numOfTickets) public  payable  {
    //     Raffle storage raffle = raffles[_raffleId];
    //     require(msg.value >= raffle.entryCost * _numOfTickets);
    //     IERC20(_token).safeTransferFrom(msg.sender, address(this), raffle.entryCost * _numOfTickets);
    // }
    function buyRaffle(
        address _token,
        uint256 _raffleId,
        uint256 _numOfTickets
    ) internal {
        Raffle storage raffle = raffles[_raffleId];
        // require(msg.value == 0, "Ether is not accepted for this transaction");
        require(
            IERC20(_token).allowance(msg.sender, address(this)) >=
                raffle.entryCost * _numOfTickets,
            "Insufficient allowance"
        );

        IERC20(_token).safeTransferFrom(
            msg.sender,
            address(this),
            raffle.entryCost * _numOfTickets
        );
    }

    function freeRaffleForMapNFTHolder(uint256 _raffleId) internal {
        Raffle storage raffle = raffles[_raffleId];
        raffle.players.push(msg.sender);
    }

    function selectWinner(uint256 _raffleId) public nonReentrant onlyOwner {
        Raffle storage raffle = raffles[_raffleId];

        require(raffle.playerSelector.length > 0, "No Player in the raffle");
        require(raffle.NFTAddress != address(0), "NFT Prize not set");

        uint256 winnerIndex = random(_raffleId) % raffle.playerSelector.length;
        address winner = raffle.playerSelector[winnerIndex];

        raffle.winner = winner;
    }

    function random(uint256 _raffleId) private view returns (uint256) {
        Raffle storage raffle = raffles[_raffleId];
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        block.timestamp,
                        raffle.players.length
                    )
                )
            );
    }

    function getMapNFTBal() public view returns (uint256) {
        return mapNFT.balanceOf(msg.sender);
    }

    function endRaffle(uint256 _raffleId) public {
        Raffle storage raffle = raffles[_raffleId];
        require(
            raffle.endTimestamp >= block.timestamp,
            "raffle has not yet ended"
        );
        raffle.endTimestamp = block.timestamp;
        raffle.raffleStatus = false;
    }

    function CheckRffleStatus(uint256 _raffleId) public view returns (bool) {
        Raffle storage raffle = raffles[_raffleId];
        return raffle.raffleStatus;
    }

    function ClaimNFTPrizeReward(uint256 _raffleId) public {
        Raffle storage raffle = raffles[_raffleId];

        // Ensure that the raffle has ended
        require(
            block.timestamp >= raffle.endTimestamp,
            "Raffle has not ended yet"
        );

        // Ensure that the caller is one of the winners
        require(raffle.players.length > 0, "No winners in the raffle");
        require(msg.sender == raffle.winner, "not a winner");

        // Perform actions to transfer the NFT prize to the caller
        // For example:
        transferNFT(
            raffle.NFTAddress,
            raffle.tokenId,
            address(this),
            msg.sender
        );

        // Emit event to indicate successful claim of NFT prize
        emit NFTPrizeClaimed(_raffleId, msg.sender);
    }

    function checkContractBal(address _token) public view returns (uint256) {
        require(address(_token) != address(0), "Token address not set");
        return IERC20(_token).balanceOf(address(this));
    }

    function withdrawContractBal(
        address _token,
        uint256 _amount
    ) public onlyOwner {
        require(_token != address(0), "Token address cannot be zero");
        return IERC20(_token).safeTransfer(address(this), _amount);
    }
}
