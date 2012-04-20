#!/bin/tcsh -f

rm -Rf /tmp/hourly_report_$1
mkdir -p /tmp/hourly_report_$1
foreach mon ( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec ) 
#    echo Reporting for $mon-$1... 1>&2
    $2 $mon-$1 "$3" "$4" > /tmp/hourly_report_$1/$mon-$1.tab
end

cp /tmp/hourly_report_$1/Jan-$1.tab /tmp/hourly_report_$1/merged-$1.tab
echo Merging Reports... 1>&2
foreach mon ( Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec ) 
    cut /tmp/hourly_report_$1/$mon-$1.tab -f 2 | paste /tmp/hourly_report_$1/merged-$1.tab - > /tmp/hourly_report_$1/merged-$1.tab.tmp
    mv -f /tmp/hourly_report_$1/merged-$1.tab.tmp /tmp/hourly_report_$1/merged-$1.tab
end

###  Add the header row...
mv /tmp/hourly_report_$1/merged-$1.tab /tmp/hourly_report_$1/merged-$1.tab.tmp
perl -e 'print join("\t",qw(Hour Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))."\n";' > /tmp/hourly_report_$1/merged-$1.tab
cat /tmp/hourly_report_$1/merged-$1.tab.tmp >> /tmp/hourly_report_$1/merged-$1.tab

exec cat /tmp/hourly_report_$1/merged-$1.tab
