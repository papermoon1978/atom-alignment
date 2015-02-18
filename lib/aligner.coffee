{Range} = require 'atom'

_ = require 'lodash'

module.exports =
    class Aligner
        # Public
        constructor: (@editor, @spaceChars, @matcher, @addSpacePostfix) ->
            @rows = []

        # Private
        __getRows: =>
            rowNums = []
            cursors = _.filter @editor.getCursors(), (cursor) ->
                row = cursor.getBufferRow()
                if cursor.visible && !_.contains(rowNums, row)
                    rowNums.push(row)
                    return true

            if (cursors.length > 1)
                @mode = "cursor"
                for cursor in cursors
                    row = cursor.getBufferRow()
                    o =
                        text   : cursor.getCurrentBufferLine()
                        length : @editor.lineTextForBufferRow(row).length
                        row    : row
                        column : cursor.getBufferColumn()
                    @rows.push (o)
            else
                ranges = @editor.getSelectedBufferRanges()
                for range in ranges
                    rowNums = rowNums.concat(range.getRows())
                    rowNums.pop() if range.end.column == 0

                for row in rowNums
                    o =
                        text   : @editor.lineTextForBufferRow(row)
                        length : @editor.lineTextForBufferRow(row).length
                        row    : row
                    @rows.push (o)

                @mode = if @rows.length > 1 then "default" else "single"

            if @mode != "cursor"
                @rows.forEach (o) ->
                    if o.text[0] == " "
                        firstCharPos  = o.text.length-o.text.trimLeft().length
                        o.text        = Array(firstCharPos).join(" ")+" "+o.text.substring(firstCharPos).replace(/\s{2,}/g, ' ')
                    else
                        o.text        = o.text.replace(/\s{2,}/g, ' ')

        __computeRows: (startPos) =>
            max = 0
            if @mode == "default" || @mode == "single" || @mode == "break"
                matched = null
                idx = -1
                @rows.forEach (o) =>
                    if !o.done
                        line = o.text
                        unless matched
                            @matcher.forEach (possibleMatcher) ->
                                unless matched
                                    if (line.indexOf(possibleMatcher, startPos) != -1)
                                        matched = possibleMatcher
                                return

                        if matched
                            idx = line.indexOf(matched, startPos)
                            if @mode == "break"
                                c = ""
                                blankPos = -1
                                quotationMark = doubleQuotationMark = backslash = charFound = false
                                loop
                                    break if c == undefined
                                    c = line[++idx]
                                    quotationMark = if c == "'" and !quotationMark and !backslash then true else false
                                    doubleQuotationMark = if c == "'" and !doubleQuotationMark and !backslash then true else false
                                    backslash = if c == "\\" and !backslash then true else false
                                    charFound = if c != " " and !charFound then true else charFound
                                    if c == " " and !quotationMark and !doubleQuotationMark and charFound
                                        blankPos = idx
                                        break

                                idx = blankPos

                            if (idx) isnt -1
                                splitString = [line.substring(0,idx), line.substring(++idx)]
                                o.splited = splitString
                                # Detection of max in this range
                                max = if max < splitString[0].length then splitString[0].length else max

                            found = false
                            @matcher.forEach (possibleMatcher) ->
                                unless found
                                    if (line.indexOf(possibleMatcher, idx+1) != -1)
                                        found = true
                                return

                            o.stop = !found

                    return

                if (max > 0)
                    addSpacePrefix = @spaceChars.indexOf(matched) > -1
                    max            = max + if addSpacePrefix then 2 else 1

                    @rows.forEach (o) =>
                        if !o.done and o.splited and matched
                            splitString = o.splited

                            diff = max - splitString[0].length

                            if diff > 0
                                splitString[0] = splitString[0] + Array(diff).join(' ')

                            splitString[1] = if @addSpacePostfix && addSpacePrefix then " "+splitString[1].trim()

                            if @mode == "break"
                                _.forEach splitString, (s, i) ->
                                    splitString[i] = s.trim()

                                o.text = splitString.join("\n")
                            else
                                o.text = splitString.join(matched)
                            o.done = o.stop
                        return
                return max
            else
                @rows.forEach (o) ->
                    max = if max < o.column then o.column else max

                max++

                @rows.forEach (o) ->
                    line = o.text
                    splitString = [line.substring(0,o.column), line.substring(o.column)]

                    diff = max - splitString[0].length

                    if diff > 0
                        splitString[0] = splitString[0] + Array(diff).join(' ')

                    splitString[1] = splitString[1].trim()

                    o.text = splitString.join("")

                return 0
        # Public
        align: (multiple) =>
            @__getRows()
            if @mode == "single" && multiple
                @mode = "break"

            if multiple || @mode == "single"
                found = 0
                loop
                    found = @__computeRows(found)
                    break if found == 0
            else
                @__computeRows(0)

            @rows.forEach (o) =>
                @editor.setTextInBufferRange([[o.row, 0],[o.row, o.length]], o.text)
