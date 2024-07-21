// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CrowdfundingDex is Ownable {
    using Strings for string;

    struct VestingInfor {
        uint256 stakeAmountInWei;
        uint256 stakeTime;
    }

    struct TokenInformation {
        string symbol;
        string swapRaito;
    }

    struct ProjectSchedule {
        uint256 createdAt;
        uint256 opensAt;
        uint256 endsAt;
    }

    struct ProjectAllocation {
        uint256 maxAllocation;
        uint256 totalRaise;
    }

    struct Project {
        uint256 id;
        address owner;
        string name;
        string slug;
        string shortDescription;
        string description;
        string logoUrl;
        string coverBackgroundUrl;
        TokenInformation tokenInformation;
        ProjectSchedule schedule;
        ProjectAllocation allocation;
        uint256 currentRaise;
        uint256 totalParticipants;
        address[] investors;
    }

    struct CreateProjectDTO {
        string name;
        string slug;
        string shortDescription;
        string description;
        string logoUrl;
        string coverBackgroundUrl;
        uint256 maxAllocation;
        uint256 totalRaise;
        string tokenSymbol;
        string tokenSwapRaito;
        uint256 opensAt;
        uint256 endsAt;
    }

    struct DexMetrics {
        uint256 totalProjects;
        uint256 uniqueParticipants;
        uint256 totalRaised;
    }

    mapping(uint256 => mapping(address => VestingInfor[])) internal projectToInvestorMap;
    //check unque user in project
    mapping(uint256 => mapping(address => bool)) internal uniqueProjectInvestorMap;
    // check investor is refunded
    mapping(uint256 => mapping(address => bool)) internal projectToInvestorRefundMap;

    // check unique user
    mapping(address => bool) internal uniqueParticipantMap;
    // check unique slug
    mapping(string => bool) internal uniqueSlugMap;

    uint256 globalProjectIdCount = 0;
    uint256 globalUniqeParticipantCount = 0;

    Project[] internal projectList;

    modifier validSender {
        if (msg.sender == address(0)) {
            revert("Invalid sender address");
        }
        _;
    }

    function createProject(CreateProjectDTO calldata dto) validSender public returns (Project memory) {
        require(!dto.name.equal(""), "Project name is required");
        require(!dto.shortDescription.equal(""), "Project headline is required");
        require(!dto.description.equal(""), "Project description is required");
        require(dto.maxAllocation > 0, "Max allocation must larger than 0");
        require(dto.totalRaise > 0, "Total raise must larger than 0");
        require(!dto.tokenSymbol.equal(""), "Missing token symbol");

        require(dto.opensAt > block.timestamp * 1000, "Open date should be a date in future");
        require(dto.endsAt > dto.opensAt, "Allocation end date should be larger than open date");

        globalProjectIdCount++;
        // create slug
        string memory projectSlug = createSlug(dto.slug);
        // slugPool.push(projectSlug);
        uniqueSlugMap[projectSlug] = true;

        Project memory project = Project(
            globalProjectIdCount,
            msg.sender,
            dto.name,
            projectSlug,
            dto.shortDescription,
            dto.description,
            dto.logoUrl,
            dto.coverBackgroundUrl,
            TokenInformation(dto.tokenSymbol, dto.tokenSwapRaito),
            ProjectSchedule(block.timestamp * 1000, dto.opensAt, dto.endsAt),
            ProjectAllocation(dto.maxAllocation, dto.totalRaise),
            0,
            0,
            new address[](0)
        );
        projectList.push(project);

        return project;
    }

    function getProjectList() public view returns (Project[] memory) {
        return projectList;
    }

    function stakingInProject(uint256 projectId) public payable validSender {
        int256 index = findIndexOfProject(projectId);
        require(index > -1, "project_not_found");

        Project storage project = projectList[uint256(index)];
        uint256 userStakeInWei = msg.value;

        // check owner self staking
        require(msg.sender != project.owner, "project_owner");

        // check stake time is early or late
        require(block.timestamp * 1000 >= project.schedule.opensAt && block.timestamp * 1000 <= project.schedule.endsAt, "staking_not_open");

        // check is full of staking or not
        require(project.allocation.totalRaise > project.currentRaise, "target_reached");

        // check min allocation
        require(userStakeInWei > 0, "not_enough");

        // check valid allocation
        VestingInfor[] storage vestingList = projectToInvestorMap[project.id][msg.sender];

        uint256 totalStakeInWei = 0;
        for (uint256 i = 0; i < vestingList.length; i++) {
            totalStakeInWei += vestingList[i].stakeAmountInWei;
        }

        require(totalStakeInWei + userStakeInWei <= project.allocation.maxAllocation, "max_allocation");
        require(project.currentRaise + userStakeInWei <= project.allocation.totalRaise, "too_much");

        // add amount to storage
        project.currentRaise += userStakeInWei;

        // add investor to project
        if (!uniqueProjectInvestorMap[project.id][msg.sender]) {
            project.totalParticipants++;
            uniqueProjectInvestorMap[project.id][msg.sender] = true;
            project.investors.push(msg.sender);
        }

        vestingList.push(VestingInfor(userStakeInWei, block.timestamp * 1000));

        // count global participant
        if (!uniqueParticipantMap[msg.sender]) {
            uniqueParticipantMap[msg.sender] = true;
            globalUniqeParticipantCount++;
        }
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getDexMetris() public view returns (DexMetrics memory) {
        uint256 totalRaised = 0;

        for (uint256 i = 0; i < projectList.length; i++) {
            totalRaised += projectList[i].currentRaise;
        }

        return DexMetrics(projectList.length, globalUniqeParticipantCount, totalRaised);
    }

    function getProjectDetail(string calldata slug) public view returns (Project memory) {
        int256 index = findIndexOfProject(slug);

        require(index > -1, "not_found");

        Project memory project = projectList[uint256(index)];
        return project;
    }

    function getProjectStakingByInvestor(uint256 projectId) public view returns (VestingInfor[] memory) {
        require(uniqueProjectInvestorMap[projectId][msg.sender], "staking_not_found");

        return projectToInvestorMap[projectId][msg.sender];
    }

    function getStakedProjectByInvestor() public view returns (Project[] memory) {
        address investor = msg.sender;

        uint256 count = 0;
        for (uint256 i = 0; i < projectList.length; i++) {
            if (uniqueProjectInvestorMap[projectList[i].id][investor]) {
                count++;
            }
        }

        Project[] memory list = new Project[](count);
        for (uint256 i = 0; i < projectList.length; i++) {
            if (uniqueProjectInvestorMap[projectList[i].id][investor]) {
                list[i] = projectList[i];
            }
        }

        return list;
    }

    function automateDeliverMoney(string calldata slug) public onlyOwner returns (string memory) {
        int256 index = findIndexOfProject(slug);
        require(index > -1, "not_found");

        Project memory project = projectList[uint256(index)];

        // Project funding still in progess
        require(block.timestamp * 1000 >= project.schedule.endsAt, "Funding period still in progress");

        // Check funding condition
        bool isFulllyFunded = project.currentRaise >= project.allocation.totalRaise * 90 / 100;

        if (isFulllyFunded) {
            require(address(this).balance >= project.currentRaise, "Contract balance is not enough");

            (bool sent,) = payable(project.owner).call{value: project.currentRaise}("");
            if (!sent) {
                return "Sending money to owner failed";
            }

            return "Successfully sent money to owner";
        }

        address[] memory investors = project.investors;
        uint count = 0;
        for (uint256 i = 0; i < project.totalParticipants; i++) {
            VestingInfor[] memory infor = projectToInvestorMap[project.id][investors[i]];

            // this investor is refunded
            if (projectToInvestorRefundMap[project.id][investors[i]]) {
                continue;
            }

            uint256 total = 0;
            for (uint256 j = 0; j < infor.length; j++) {
                total += infor[j].stakeAmountInWei;
            }

            (bool sent,) = payable(investors[i]).call{value: total}("");
            if (sent) {
                projectToInvestorRefundMap[project.id][investors[i]] = true;
                count++;
            }
        }

        return string.concat("Successfully sent money to ", Strings.toString(count), " investors");
    }

    function createSlug(string calldata str) private view returns (string memory) {
        string memory slug = str;
        while (uniqueSlugMap[slug]) {
            uint256 randNum = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)));
            slug = string.concat(str, "-", Strings.toString(randNum));
        }

        return slug;
    }

    function findIndexOfProject(uint256 projectId) private view returns (int256) {
        for (uint256 i = 0; i < projectList.length; i++) {
            if (projectList[i].id == projectId) {
                return int256(i);
            }
        }
        return -1;
    }

    function findIndexOfProject(string calldata slug) private view returns (int256) {
        for (uint256 i = 0; i < projectList.length; i++) {
            if (projectList[i].slug.equal(slug)) {
                return int256(i);
            }
        }
        return -1;
    }
}
