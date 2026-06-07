// Case-insensitive string comparison using built-in function
bool StringCompareCI(string str1, string str2)
{
    return StringCompare(StringUpperCase(str1), StringUpperCase(str2)) == 0;
}
