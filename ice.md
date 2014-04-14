rfc5245
========

#状态图#
!状态图(img/state.jpg "rfc5245状态图")

#数据结构:
##checklist:
<table>
    <tr><td>sid</td><td>cid</td><td>state</td><td>check_timer</td><td>pairs</td></tr>
</table>
##validlist:
<table>
    <tr><td>sid</td><td>cid</td><td>state</td><td>nominate_timer</td><td>pairs</td></tr>
</table>
##checkpair:
<table>
    <tr><td>id</td><td>sid</td><td>cid</td><td>state</td><td>local</td><td>remote</td><td>nominated</td></tr>
</table>
##check_tx:
<table>
    <tr><td>txid</td><td>pair</td><td>rto_timer</td></tr>
</table>
##candidate
