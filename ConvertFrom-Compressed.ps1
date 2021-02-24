function ConvertFrom-Compressed {
    # Uncompress a file compressed with the ConvertTo-Compressed() function
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
            [string[]]$Path,

        [Alias('T','Target')]
            $TargetDir = '.\', # Directory where the new files will be put in

            [string]$Prefix = 'compressed_', # Prefix we take off the old files
            [string]$TargetPrefix = 'decompressed_', # Prefix we give to the new files
            [switch]$WhatIf, # DO NOT WORK FOR NOW; Do everything but don't create any nor remove any file.
            [switch]$NoBeep # No sound played when finished
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
        $decompressedFiles = @(
            $Files | % {
                try {
                    $fs = [IO.FileStream]::New($_.FullName, 'Open') # Absolute path
                    $rawContent = [Byte[]]::New($fs.Length)
                    $null = $fs.Read($rawContent, 0, $fs.Length) # Destination, offset, count

                    New-Object -TypeName PSCustomObject -Property @{
                        FileName = $_.Name
                        DecompressedFileName = $TargetDir.FullName + '\' + $TargetPrefix + $_.Name.Replace($Prefix, '')
                        RawContent = $rawContent
                    }
                }
                finally {
                    $null = $fs.Close()
                }
            }
        )

        # Remove content if file already exists
        if(!($WhatIf)) { Clear-Content $decompressedFiles.DecompressedFileName -ErrorAction Ignore }

        foreach ($file in $decompressedFiles)
        {
            $sw = [Diagnostics.StopWatch]::StartNew()
            $fs = [IO.FileStream]::New($file.DecompressedFileName, 'Create') # Absolute path

            $nb = $true # Tells if we're reading the number of characters or the character
            $cpt = 0 # The number of characters
            $zeros = 0 # Number of 0's in a row

            foreach ($b in $file.RawContent)
            {
                if($nb){
                    # If 0, we don't know the number yet; we need to loop.
                    if($b -eq 0)
                    {
                        $zeros++
                        $nb = $false # To re-enable the check on the next turn
                    }
                    else {
                        # If it is not 0 and it was zero before, we have the total number of 0's now.
                        if($zeros)
                        {
                            $cpt = $zeros * 256 + $b
                            $zeros = 0
                        }
                        # If it wasn't, we directly have the cpt.
                        else { $cpt = $b }
                    }
                }
                else {
                    # an array with $cpt times $b
                    $fs.Write((,$b) * $cpt, 0, $cpt) # source, offset, count
                }
                $nb = !($nb)
            }
            
            # Finished
            $fs.Close()
            $sw.Stop()
            Write-Verbose ('Done decompressing: ' + $file.FileName + "($([Math]::Round($sw.Elapsed.TotalSeconds,5)) seconds)" )
        }
    }
    
    END {

        # Output the old names on the left and the new names on the right
        Write-Verbose ("`r`nDecompressed files summary:`r`n" + (
            $decompressedFiles | Select-Object -Property FileName, DecompressedFileName | Out-String))

        if($WhatIf) { Remove-Item (Get-Item $parentDir) -Force -Recurse }
        if(!$NoBeep) { [Media.Systemsounds]::Beep.Play() }
    }
}
