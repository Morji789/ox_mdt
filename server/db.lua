local db = {}
local selectCharacter = 'SELECT `firstName`, `lastName`, DATE_FORMAT(`dateofbirth`, "%Y-%m-%d") as dob, `stateId` FROM `characters`'
local wildcard = '%s%%'
local selectCharacterById = selectCharacter .. ' WHERE `stateId` LIKE ?'
local framework = require 'server.framework.ox_core'

---@param id number | string
function db.selectCharacterById(id)
    return MySQL.rawExecute.await(selectCharacterById, { wildcard:format(id) })
end

local selectCharacterByNameA = selectCharacter .. ' WHERE `lastName` LIKE ? OR `stateId` LIKE ?'
local selectCharacterByNameB = selectCharacter .. ' WHERE `firstName` = ? AND `lastName` LIKE ?'

---@param name string
function db.selectCharacterByName(name)
    local nameA, nameB = name:match('^([%w]+) ?([%w]*)$')

    if nameB == '' then
        nameA = wildcard:format(nameA)

        return MySQL.rawExecute.await(selectCharacterByNameA, { nameA, nameA })
    end

    return MySQL.rawExecute.await(selectCharacterByNameB, { nameA, wildcard:format(nameB) })
end

---@param title string
---@param author string
function db.createReport(title, author)
    return MySQL.prepare.await('INSERT INTO `ox_mdt_reports` (`title`, `author`) VALUES (?, ?)', { title, author }) --[[@as number?]]
end

---@param id number
function db.selectReportById(id)
    return MySQL.prepare.await('SELECT `id`, `title`, `description` FROM `ox_mdt_reports` WHERE `id` = ?', { id }) --[[@as MySQLRow]]
end

local selectReports = 'SELECT `id`, `title`, `author`, DATE_FORMAT(`date`, "%Y-%m-%d %T") as date FROM `ox_mdt_reports`'
local selectReportsById = selectReports .. 'WHERE `id` LIKE ?'

---@param id number | string
function db.selectReportsById(id)
    return MySQL.rawExecute.await(selectReportsById, { wildcard:format(id) })
end

local selectReportsByString = selectReports .. ' WHERE `title` LIKE ? or `author` LIKE ? or `date` LIKE ? ORDER BY `date` DESC LIMIT 10 OFFSET ?'

---@param page number
---@param search string
function db.selectReports(page, search)
    search = wildcard:format(search)
    return MySQL.rawExecute.await(selectReportsByString, { search, search, search, (page - 1) * 10 })
end

---@param stateId string
---@param image string | nil
function db.updateProfileImage(stateId, image)
    return MySQL.rawExecute.await('INSERT INTO `ox_mdt_profiles` (`stateid`, `image`, `notes`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `image` = ?', { stateId, image, nil, image })
end

---@param stateId string
---@param notes string
function db.updateProfileNotes(stateId, notes)
    return MySQL.rawExecute.await('INSERT INTO `ox_mdt_profiles` (`stateid`, `image`, `notes`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `notes` = ?', { stateId, nil, notes, notes })
end

---@param id number
function db.deleteReport(id)
    return MySQL.prepare.await('DELETE FROM `ox_mdt_reports` WHERE `id` = ?', { id }) --[[@as number?]]
end

---@param title string
---@param reportId number
function db.updateReportTitle(title, reportId)
    return MySQL.prepare.await('UPDATE `ox_mdt_reports` SET `title` = ? WHERE `id` = ?', { title, reportId }) --[[@as number?]]
end

---@param page number
---@param search string
---@return ProfileCard[]?
function db.selectProfiles(page, search)
    local offset = (page - 1) * 10

    -- todo: search based on name or stateid
    return MySQL.rawExecute.await('SELECT a.stateId, a.firstName, a.lastName, DATE_FORMAT(a.dateofbirth, "%Y-%m-%d") AS dob, b.image FROM `characters` a LEFT JOIN `ox_mdt_profiles` b ON b.stateid = a.stateid LIMIT 10 OFFSET ?', { offset })

end

function db.selectOfficersInvolved(reportId)
    local officers = MySQL.rawExecute.await('SELECT b.firstName, b.lastName, b.stateId FROM `ox_mdt_reports_officers` a LEFT JOIN `characters` b ON b.stateId = a.stateId WHERE `reportid` = ?', { reportId }) or {}
    print(json.encode(officers, {sort_keys=true,indent=true}))
    return officers
end

function db.selectCriminalsInvolved(reportId)
    local parameters = { reportId }

    ---@type { stateId: number | string, firstName: string, lastName: string, reduction: number, warrantExpiry?: string, processed?: number | boolean, pleadedGuilty?: number | boolean }[]
    local criminals = MySQL.rawExecute.await('SELECT DISTINCT a.stateId, b.firstName, b.lastName, a.reduction, DATE_FORMAT(a.warrantExpiry, "%Y-%m-%d") AS warrantExpiry, a.processed, a.pleadedGuilty FROM `ox_mdt_reports_criminals` a LEFT JOIN `characters` b on b.stateId = a.stateId WHERE reportid = ?', parameters) or {}

    ---@type { stateId: number | string, label: string, time: number?, fine: number?, points: number?, count: number }[]
    local charges = MySQL.rawExecute.await('SELECT `stateId`, `charge` as label, `time`, `fine`, `points`, `count` FROM `ox_mdt_reports_charges` WHERE reportid = ? GROUP BY `charge`, `stateId`', parameters) or {}

    for _, criminal in pairs(criminals) do
        ---@type SelectedCharge[]
        criminal.charges = {}
        local chargesN = 0

        criminal.penalty = {
            time = 0,
            fine = 0,
            points = 0,
            reduction = criminal.reduction
        }

        for _, charge in pairs(charges) do
            if charge.label and charge.stateId == criminal.stateId then
                charge.penalty = {
                    time = charge.time or 0,
                    fine = charge.fine or 0,
                    points = charge.points or 0
                }

                charge.stateId, charge.time, charge.fine, charge.points = nil
                criminal.penalty.time += charge.penalty.time
                criminal.penalty.fine += charge.penalty.fine
                criminal.penalty.points += charge.penalty.points
                chargesN += 1
                criminal.charges[chargesN] = charge
            end
        end

        if criminal.warrantExpiry then
            criminal.issueWarrant = true
        end

        criminal.processed = criminal.processed or false
        criminal.pleadedGuilty = criminal.pleadedGuilty or false
        print(json.encode(criminal.processed), type(criminal.processed))
    end

    return criminals
end

function db.selectEvidence(reportId)
    return MySQL.rawExecute.await('SELECT `label`, `value`, `type` FROM `ox_mdt_reports_evidence` WHERE reportid = ?', { reportId })
end

---@param reportId number
---@param criminal Criminal
function db.saveCriminal(reportId, criminal)
    local queries = {
        { 'DELETE FROM `ox_mdt_reports_charges` WHERE `reportid` = ? AND `stateId` = ?', { reportId, criminal.stateId } },
        { 'UPDATE IGNORE `ox_mdt_reports_criminals` SET `warrantExpiry` = ?, `processed` = ?, `pleadedGuilty` = ? WHERE `reportid` = ? AND `stateId` = ?', { criminal.issueWarrant and criminal.warrantExpiry or nil, criminal.processed, criminal.pleadedGuilty, reportId, criminal.stateId } },
    }
    local queryN = #queries

    print(json.encode(criminal, {indent=true,sort_keys=true}))

    if next(criminal.charges) then
        for _, v in pairs(criminal.charges) do
            queryN += 1
            ---@todo fetch and store all criminal offenses; use time, fine, and points
            queries[queryN] = { 'INSERT INTO `ox_mdt_reports_charges` (`reportid`, `stateId`, `charge`, `count`, `time`, `fine`, `points`) VALUES (?, ?, ?, ?, ?, ?, ?)', { reportId, criminal.stateId, v.label, v.count } }
        end
    end

    return MySQL.transaction.await(queries)
end

function db.removeCriminal(reportId, stateId)
    return MySQL.prepare.await('DELETE FROM `ox_mdt_reports_criminals` WHERE `reportid` = ? AND `stateId` = ?', { reportId, stateId })
end

---@param reportId number
---@param stateId string | number
function db.addCriminal(reportId, stateId)
    return MySQL.prepare.await('INSERT INTO `ox_mdt_reports_criminals` (`reportid`, `stateId`) VALUES (?, ?)', { reportId, stateId }) --[[@as number?]]
end

---@param search string | number
---@return Profile?
function db.selectCharacterProfile(search)
    local parameters = { search }
    local profile = MySQL.rawExecute.await('SELECT a.firstName, a.lastName, a.stateId, a.charid, DATE_FORMAT(a.dateofbirth, "%Y-%m-%d") AS dob, a.phone_number AS phoneNumber, b.image, b.notes FROM `characters` a LEFT JOIN `ox_mdt_profiles` b ON b.stateid = a.stateid WHERE a.stateId = ?', parameters)?[1]

    if not profile then return end

    profile.relatedReports = MySQL.rawExecute.await('SELECT DISTINCT `id`, `title`, `author`, DATE_FORMAT(`date`, "%Y-%m-%d") as date FROM `ox_mdt_reports` a LEFT JOIN `ox_mdt_reports_charges` b ON b.reportid = a.id WHERE `stateId` = ?', parameters) or {}
    profile.pastCharges = MySQL.rawExecute.await('SELECT `charge` AS label, SUM(`count`) AS count FROM `ox_mdt_reports_charges` WHERE `charge` IS NOT NULL AND `stateId` = ? GROUP BY `charge`', parameters) or {}

    parameters[1] = profile.charid
    profile.vehicles = framework.getVehicles(parameters)
    profile.licenses = framework.getLicenses(parameters)

    return profile
end

local selectOfficerInvolved = [[
    SELECT
        firstName,
        lastName,
        characters.stateId,
        character_groups.grade AS grade,
        ox_mdt_profiles.callSign
    FROM
        character_groups
    LEFT JOIN
        characters
    ON
        character_groups.charid = characters.charid
    LEFT JOIN
        ox_mdt_profiles
    ON
        characters.stateId = ox_mdt_profiles.stateId
    WHERE
        character_groups.name = "police"
]]

local selectOfficerInvolvedByNameA = selectOfficerInvolved .. ' AND (`lastName` LIKE ? OR ox_mdt_profiles.callsign LIKE ?)'
local selectOfficerInvolvedByNameB = selectOfficerInvolved .. ' AND (`firstName` = ? AND `lastName` LIKE ?)'

---@param search string | number
---@return Officer | Officer[] | nil
function db.selectInvolvedOfficers(search)
    if not search then
        return MySQL.rawExecute.await(selectOfficerInvolved)
    end

    local nameA, nameB = search:match('^([%w]+) ?([%w]*)$')

    if nameB == '' then
        nameA = wildcard:format(nameA)

        return MySQL.rawExecute.await(selectOfficerInvolvedByNameA, { nameA, nameA })
    end

    return MySQL.rawExecute.await(selectOfficerInvolvedByNameB, { nameA, wildcard:format(nameB) })
end

---@param reportId number
---@param stateId number
function db.addOfficer(reportId, stateId)
    return MySQL.prepare.await('INSERT INTO `ox_mdt_reports_officers` (`reportid`, `stateId`) VALUES (?, ?)', { reportId, stateId })
end

---@param reportId number
---@param stateId number
function db.removeOfficer(reportId, stateId)
    return MySQL.prepare.await('DELETE FROM `ox_mdt_reports_officers` WHERE `reportid` = ? AND `stateId` = ?', { reportId, stateId })
end

---@param id number
---@param type 'image' | 'item'
---@param label string
---@param value string | number 
function db.addEvidence(id, type, label, value)
    return MySQL.prepare.await('INSERT INTO `ox_mdt_reports_evidence` (`reportid`, `label`, `value`, `type`) VALUES (?, ?, ?, ?)', { id, label, value, type })
end

---@param id number
---@param label string
---@param value string
function db.removeEvidence(id, label, value)
    return MySQL.prepare.await('DELETE FROM `ox_mdt_reports_evidence` WHERE `reportid` = ? AND `label` = ? AND `value` = ?', { id, label, value })
end

---@param id number
---@param value string
function db.updateReportContents(id, value)
    return MySQL.prepare.await('UPDATE `ox_mdt_reports` SET `description` = ? WHERE `id` =  ?', { value, id })
end

---@param page number
function db.selectAnnouncements(page)
     return MySQL.rawExecute.await('SELECT a.id, a.contents, a.creator AS stateId, b.firstName, b.lastName, DATE_FORMAT(a.createdAt, "%Y-%m-%d %T") AS createdAt FROM `ox_mdt_announcements` a LEFT JOIN `characters` b ON b.stateId = a.creator ORDER BY `createdAt` DESC LIMIT 5 OFFSET ?', { (page - 1) * 5 })
end

---@param creator string
---@param contents string
function db.createAnnouncement(creator, contents)
    return MySQL.prepare.await('INSERT INTO `ox_mdt_announcements` (`creator`, `contents`) VALUES (?, ?)', { creator, contents })
end

---@param id number
---@param contents string
function db.updateAnnouncementContents(id, contents)
    return MySQL.prepare.await('UPDATE `ox_mdt_announcements` SET `contents` = ? WHERE `id` = ?', { contents, id })
end

---@param id number
function db.removeAnnouncement(id)
    return MySQL.prepare.await('DELETE FROM `ox_mdt_announcements` WHERE `id` = ?', { id })
end

local selectWarrants = 'SELECT a.reportId, a.stateId, b.firstName, b.lastName, DATE_FORMAT(a.expiresAt, "%Y-%m-%d %T") AS expiresAt FROM `ox_mdt_warrants` a LEFT JOIN `characters` b ON a.stateid = b.stateid'
local selectWarrantsA = selectWarrants .. ' WHERE `lastName` LIKE ? OR a.stateId LIKE ?'
local selectWarrantsB = selectWarrants .. ' WHERE `firstName` = ? AND `lastName` LIKE ?'

---@param search string
function db.selectWarrants(search)
    if search == '' then return MySQL.rawExecute.await(selectWarrants) end

    local nameA, nameB = search:match('^([%w]+) ?([%w]*)$')

    if nameB == '' then
        nameA = wildcard:format(nameA)

        return MySQL.rawExecute.await(selectWarrantsA, { nameA, nameA })
    end

    return MySQL.rawExecute.await(selectWarrantsB, { nameA, wildcard:format(nameB) })
end

function db.createWarrant(reportId, stateId, expiry)
    return MySQL.prepare.await('INSERT INTO `ox_mdt_warrants` (`reportid`, `stateid`, `expiresAt`) VALUES (?, ?, ?)', { reportId, stateId, expiry })
end

function db.removeWarrant(reportId, stateId)
    return MySQL.prepare.await('DELETE FROM `ox_mdt_warrants` WHERE `reportid` = ? AND `stateid` = ?', { reportId, stateId })
end

return db
