#!/bin/bash
ls -l /root/kbtest-*.log 2>/dev/null
echo "--- image build tail ---"
tail -6 /root/kbtest-image.log 2>/dev/null
echo "--- modules tail ---"
tail -3 /root/kbtest-mod3.log 2>/dev/null
echo "--- dtbs(final, after fixes) ---"
tail -4 /root/kbtest-dtbs3.log 2>/dev/null
