function ConvertTo-Compressed {
    # Compress a file with an implementation of the RLE algorithm (Run-Length Encoding)
    [CmdletBinding(DefaultParameterSetName='Default')]
    param(
        [Parameter(ParameterSetName='Default', Mandatory, Position=0, ValueFromPipeline)]
        [Parameter(ParameterSetName='Remove', Mandatory, Position=0, ValueFromPipeline)]
            [string[]]$Path,

        [Parameter(ParameterSetName='Default', Position=1, ValueFromPipeline)]
        [Parameter(ParameterSetName='Remove', Position=1, ValueFromPipeline)]
        [Alias('T','Target')]
            $TargetDir = '.\', # Directory where the new files will be put in

        [Parameter(ParameterSetName='Default', Position=3)]
        [Parameter(ParameterSetName='Remove', Position=3)]
            [string]$TargetPrefix = 'compressed_', # Prefix we give to the new files

        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='Remove')]
            [switch]$WhatIf, # DO NOT WORK FOR NOW; Do everything but don't create nor remove any file.
        
        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='Remove')]
        [switch]$NoBeep, # Don't  when finished

        [Parameter(ParameterSetName='Remove', Mandatory)]
        [Alias('R')]
            [switch]$RemoveOriginal, # Deletes original files

        [Parameter(ParameterSetName='Remove')]
        [Alias('Y','Yes','NoConfirm')]
            [switch]$YesRemove # Don't ask confirmation before deleting the files
    )

    BEGIN {

        # If we don't want to do anything, create a temporary directory just so the paths are correct
        if($WhatIf)
        {
            $parentDir = ("$env:TMP\" + $((New-Guid).Guid))
            $TargetDir = ($parentDir + '\' + $TargetDir)
        }
        
        # Create the directory if it doesn't exist
        if(!(Test-Path $TargetDir -PathType Container)) {
            $null = (New-Item -Path $TargetDir -ItemType Directory)
            Write-Verbose "Created directory '$TargetDir'"
        }

        # Expand $TargetDir to a DirectoryInfo object
        $TargetDir = (Get-Item $TargetDir)
    }

    PROCESS {

        # If the $Path doesn't match any file
        if(!(Test-Path $Path)) { Write-Warning "No file found with path '$Path'" ; return }

        $Files = @(Get-ChildItem $Path -Attributes !D) # Not the directories
        # Note: the '@' forces the array type

        if($Files.Length -eq 0) { Write-Warning "No file found with path '$Path'" ; return }

        # An array with each element being the content of a file
        $bytes = @($Files | % {Get-Content $_ -Raw -AsByteStream})
        
        # An array with the new files' informations and contents
        $compressedFiles = @(
            $Files | % {
                try {
                    $fs = [IO.FileStream]::New($_.FullName, 'Open') # Absolute path
                    $rawContent = [Byte[]]::New($fs.Length)
                    $null = $fs.Read($rawContent, 0, $fs.Length) # Destination, offset, count

                    New-Object -TypeName PSCustomObject -Property @{
                        FileName = $_.Name
                        CompressedFileName = $TargetDir.FullName + '\' + $TargetPrefix + $_.Name
                        RawContent = $rawContent
                    }
                }
                finally {
                    $null = $fs.Close()
                }
            }
        )

        # Remove content if file already exists
        if(!($WhatIf)) { Clear-Content $compressedFiles.CompressedFileName -ErrorAction Ignore }

        foreach ($file in $compressedFiles)
        {
            $sw = [Diagnostics.StopWatch]::StartNew()
            try {
                $fs = [IO.FileStream]::New($file.CompressedFileName, 'Create') # Absolute path

                $cpt = 0 # Number of times the current character has appeared so far
                $precByte = $file.RawContent[0]

                foreach ($b in $file.RawContent)
                {
                    # If it's the same as the previous one
                    if($b -eq $precByte) { $cpt ++ }
                    else
                    {
                        # Protection for the times a character appears > 255 times
                        while ($cpt -gt 255)
                        {
                            # '0' is a special flag to say '256', we write it while we have > 255 characters.
                            $fs.WriteByte(0)
                            $cpt -= 256 # Decrement of 256
                        }
                        
                        $fs.WriteByte($cpt)
                        $fs.WriteByte($precByte) # The character
                        
                        $precByte = $b
                        $cpt = 1 # We have one occurrence of the new character now
                    }
                    # Maybe do something here to inform of the progression for this file
                }
                # We didn't write the last byte
                # Note: I can't get it to work correctly without writing this twice
                while ($cpt -gt 255)
                {
                    # '0' is a special flag to say '256', we write it while we have > 255 characters.
                    $fs.WriteByte(0)
                    $cpt -= 256 # Decrement of 256
                }
                
                $fs.WriteByte($cpt)
                $fs.WriteByte($precByte) # The character
            }
            # Finished
            finally {
                $fs.Close()
            }
            $sw.Stop()
            Write-Verbose ('Done compressing: ' + $file.FileName + "($([Math]::Round($sw.Elapsed.TotalSeconds,5)) seconds)" )
        }
    }

    END {

        # Output the old names on the left and the new names on the right
        Write-Verbose ("`r`nCompressed files summary:`r`n" + (
            $compressedFiles | Select-Object -Property FileName, CompressedFileName | Out-String))
        
        if($RemoveOriginal) {
            if(!($WhatIf))
            {
                if($YesRemove) { Remove-Item $Files }
                else { Remove-Item $Files -Confirm }
            }

            Write-Verbose ('Deleted files:' + ($Files | Out-String))
        }

        if($WhatIf) { Remove-Item (Get-Item $parentDir) -Force -Recurse }
        if(!$NoBeep) { [Media.Systemsounds]::Beep.Play() }
    }
}
